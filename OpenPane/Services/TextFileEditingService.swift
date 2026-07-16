//
//  TextFileEditingService.swift
//  OpenPane
//

import Darwin
import Foundation
import UniformTypeIdentifiers

nonisolated enum TextFileEncoding: Equatable, Sendable {
    case utf8(hasByteOrderMark: Bool)
    case utf16LittleEndian(hasByteOrderMark: Bool)
    case utf16BigEndian(hasByteOrderMark: Bool)

    var hasByteOrderMark: Bool {
        switch self {
        case .utf8(let hasByteOrderMark),
             .utf16LittleEndian(let hasByteOrderMark),
             .utf16BigEndian(let hasByteOrderMark):
            return hasByteOrderMark
        }
    }

    var displayName: String {
        switch self {
        case .utf8:
            return "UTF-8"
        case .utf16LittleEndian:
            return "UTF-16 Little Endian"
        case .utf16BigEndian:
            return "UTF-16 Big Endian"
        }
    }
}

nonisolated struct TextFileFingerprint: Equatable, Sendable {
    let deviceID: UInt64
    let fileID: UInt64
    let byteCount: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
}

nonisolated struct EditableTextDocument: Equatable, Sendable {
    let url: URL
    let text: String
    let encoding: TextFileEncoding
    let fingerprint: TextFileFingerprint
}

nonisolated enum TextEditEligibility: Equatable, Sendable {
    case eligible
    case directory
    case package
    case symbolicLink
    case notRegularFile
    case notText
    case tooLarge(byteCount: Int64, limit: Int64)
    case unreadable
}

nonisolated enum TextSaveConflictPolicy: Equatable, Sendable {
    case failIfChanged
    case overwrite
}

nonisolated enum TextFileEditingError: LocalizedError, Equatable, Sendable {
    case notEligible(TextEditEligibility)
    case invalidTextEncoding(URL)
    case binaryFile(URL)
    case fileChanged(URL)
    case unsafeItem(URL)
    case cannotRead(URL, String)
    case cannotEncode(URL)
    case cannotSave(URL, String)

    var errorDescription: String? {
        switch self {
        case .notEligible(.directory):
            return "Folders cannot be edited as text."
        case .notEligible(.package):
            return "Packages cannot be edited as text."
        case .notEligible(.symbolicLink):
            return "Symbolic links cannot be edited in place."
        case .notEligible(.notText):
            return "This file is not recognized as a text file."
        case .notEligible(.tooLarge(_, let limit)):
            return "Quick editing is limited to \(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file))."
        case .notEligible(.unreadable):
            return "This file cannot be read."
        case .notEligible:
            return "This item cannot be edited as text."
        case .invalidTextEncoding(let url):
            return "\(url.lastPathComponent) is not valid UTF-8 or UTF-16 text."
        case .binaryFile(let url):
            return "\(url.lastPathComponent) appears to be a binary file."
        case .fileChanged(let url):
            return "\(url.lastPathComponent) changed after it was opened."
        case .unsafeItem(let url):
            return "\(url.lastPathComponent) is no longer a regular file."
        case .cannotRead(let url, let reason):
            return "Could not read \(url.lastPathComponent): \(reason)"
        case .cannotEncode(let url):
            return "Could not encode the edited text for \(url.lastPathComponent)."
        case .cannotSave(let url, let reason):
            return "Could not save \(url.lastPathComponent): \(reason)"
        }
    }
}

nonisolated protocol TextFileEditingServicing: Sendable {
    nonisolated func inspect(url: URL) async -> TextEditEligibility
    nonisolated func load(url: URL) async throws -> EditableTextDocument
    nonisolated func save(
        document: EditableTextDocument,
        text: String,
        conflictPolicy: TextSaveConflictPolicy
    ) async throws -> EditableTextDocument
}

extension TextFileEditingServicing {
    nonisolated func save(
        document: EditableTextDocument,
        text: String
    ) async throws -> EditableTextDocument {
        try await save(document: document, text: text, conflictPolicy: .failIfChanged)
    }
}

/// Loads only explicitly supported text files and publishes edits through a
/// metadata-preserving sibling staging file. Mounted shares use the same URL
/// path, so failures leave both the original file and the in-memory draft
/// untouched.
nonisolated struct TextFileEditingService: TextFileEditingServicing {
    nonisolated static let maximumEditableByteCount: Int64 = 10 * 1_024 * 1_024

    private static let readChunkSize = 64 * 1_024
    private static let utf8ByteOrderMark = Data([0xEF, 0xBB, 0xBF])
    private static let utf16LittleEndianByteOrderMark = Data([0xFF, 0xFE])
    private static let utf16BigEndianByteOrderMark = Data([0xFE, 0xFF])

    private let fileSystem: any FileSystemOperating
    private let transferService: any FileTransferServicing

    nonisolated init(
        fileSystem: any FileSystemOperating = FileManagerFileSystem(),
        transferService: any FileTransferServicing = CopyfileTransferService()
    ) {
        self.fileSystem = fileSystem
        self.transferService = transferService
    }

    nonisolated func inspect(url: URL) async -> TextEditEligibility {
        (try? await Self.performUserInitiated {
            Self.inspectSynchronously(url: url)
        }) ?? .unreadable
    }

    nonisolated func load(url: URL) async throws -> EditableTextDocument {
        do {
            return try await Self.performUserInitiated {
                let eligibility = Self.inspectSynchronously(url: url)
                guard eligibility == .eligible else {
                    throw TextFileEditingError.notEligible(eligibility)
                }

                let loadedData = try Self.readData(at: url)
                let decoded = try Self.decode(loadedData, url: url)
                let fingerprint = try Self.fingerprint(at: url)
                return EditableTextDocument(
                    url: url,
                    text: decoded.text,
                    encoding: decoded.encoding,
                    fingerprint: fingerprint
                )
            }
        } catch let error as TextFileEditingError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TextFileEditingError.cannotRead(url, Self.userReadableReason(for: error))
        }
    }

    nonisolated func save(
        document: EditableTextDocument,
        text: String,
        conflictPolicy: TextSaveConflictPolicy
    ) async throws -> EditableTextDocument {
        let fileSystem = fileSystem
        let transferService = transferService

        do {
            return try await Self.performUserInitiated {
                try Task.checkCancellation()
                let url = document.url
                let currentFingerprint = try Self.fingerprint(at: url)
                if conflictPolicy == .failIfChanged,
                   currentFingerprint != document.fingerprint {
                    throw TextFileEditingError.fileChanged(url)
                }

                let encodedData = try Self.encode(text, as: document.encoding, url: url)
                guard encodedData.count <= Self.maximumEditableByteCount else {
                    throw TextFileEditingError.notEligible(
                        .tooLarge(
                            byteCount: Int64(encodedData.count),
                            limit: Self.maximumEditableByteCount
                        )
                    )
                }

                let stagingURL = Self.uniqueStagingURL(
                    beside: url,
                    fileSystem: fileSystem
                )
                var ownsStagingFile = false
                defer {
                    if ownsStagingFile {
                        try? fileSystem.removeItem(at: stagingURL)
                    }
                }

                do {
                    try transferService.copyItem(
                        at: url,
                        to: stagingURL,
                        progressHandler: { _ in },
                        isCancelled: { Task.isCancelled }
                    )
                    ownsStagingFile = true
                } catch {
                    if !Self.isDestinationExistsError(error) {
                        // A failed copyfile operation can leave a partial file.
                        // The UUID path did not exist before the exclusive copy,
                        // so this process owns that partial result.
                        try? fileSystem.removeItem(at: stagingURL)
                    }
                    throw error
                }

                try Task.checkCancellation()
                guard try Self.entryType(at: stagingURL) == S_IFREG else {
                    throw TextFileEditingError.unsafeItem(stagingURL)
                }

                let fileHandle = try FileHandle(forWritingTo: stagingURL)
                do {
                    try fileHandle.truncate(atOffset: 0)
                    try fileHandle.write(contentsOf: encodedData)
                    try fileHandle.synchronize()
                    try fileHandle.close()
                } catch {
                    try? fileHandle.close()
                    throw error
                }

                try Task.checkCancellation()
                if conflictPolicy == .failIfChanged,
                   try Self.fingerprint(at: url) != document.fingerprint {
                    throw TextFileEditingError.fileChanged(url)
                }

                try fileSystem.replaceItem(at: url, withItemAt: stagingURL)
                let savedFingerprint = try Self.fingerprint(at: url)
                return EditableTextDocument(
                    url: url,
                    text: text,
                    encoding: document.encoding,
                    fingerprint: savedFingerprint
                )
            }
        } catch let error as TextFileEditingError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TextFileEditingError.cannotSave(
                document.url,
                Self.userReadableReason(for: error)
            )
        }
    }

    private nonisolated static func performUserInitiated<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try operation()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func inspectSynchronously(url: URL) -> TextEditEligibility {
        let type: mode_t
        do {
            type = try entryType(at: url)
        } catch {
            return .unreadable
        }

        if type == S_IFLNK {
            return .symbolicLink
        }

        let keys: Set<URLResourceKey> = [
            .isPackageKey,
            .fileSizeKey,
            .contentTypeKey,
            .typeIdentifierKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return .unreadable
        }

        if values.isPackage == true {
            return .package
        }
        if type == S_IFDIR {
            return .directory
        }
        guard type == S_IFREG else {
            return .notRegularFile
        }

        let byteCount = Int64(values.fileSize ?? 0)
        guard byteCount <= maximumEditableByteCount else {
            return .tooLarge(byteCount: byteCount, limit: maximumEditableByteCount)
        }

        let contentType = values.contentType
            ?? values.typeIdentifier.flatMap(UTType.init)
            ?? UTType(filenameExtension: url.pathExtension)
        guard contentType?.conforms(to: .text) == true else {
            return .notText
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .unreadable
        }

        return .eligible
    }

    private nonisolated static func readData(at url: URL) throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        var data = Data()
        data.reserveCapacity(min(Int(maximumEditableByteCount), readChunkSize))

        while true {
            try Task.checkCancellation()
            let remainingAllowance = Int(maximumEditableByteCount) + 1 - data.count
            guard remainingAllowance > 0 else {
                throw TextFileEditingError.notEligible(
                    .tooLarge(
                        byteCount: Int64(data.count),
                        limit: maximumEditableByteCount
                    )
                )
            }
            let chunk = try fileHandle.read(upToCount: min(readChunkSize, remainingAllowance)) ?? Data()
            if chunk.isEmpty {
                return data
            }
            data.append(chunk)
            if data.count > maximumEditableByteCount {
                throw TextFileEditingError.notEligible(
                    .tooLarge(
                        byteCount: Int64(data.count),
                        limit: maximumEditableByteCount
                    )
                )
            }
        }
    }

    private nonisolated static func decode(
        _ data: Data,
        url: URL
    ) throws -> (text: String, encoding: TextFileEncoding) {
        if data.starts(with: utf8ByteOrderMark) {
            let payload = data.dropFirst(utf8ByteOrderMark.count)
            guard let text = String(data: payload, encoding: .utf8) else {
                throw TextFileEditingError.invalidTextEncoding(url)
            }
            try rejectBinaryText(text, url: url)
            return (text, .utf8(hasByteOrderMark: true))
        }

        if data.starts(with: utf16LittleEndianByteOrderMark) {
            return try decodeUTF16(
                Data(data.dropFirst(utf16LittleEndianByteOrderMark.count)),
                foundationEncoding: .utf16LittleEndian,
                encoding: .utf16LittleEndian(hasByteOrderMark: true),
                url: url
            )
        }

        if data.starts(with: utf16BigEndianByteOrderMark) {
            return try decodeUTF16(
                Data(data.dropFirst(utf16BigEndianByteOrderMark.count)),
                foundationEncoding: .utf16BigEndian,
                encoding: .utf16BigEndian(hasByteOrderMark: true),
                url: url
            )
        }

        if let endian = inferredUTF16Endian(from: data) {
            switch endian {
            case .little:
                return try decodeUTF16(
                    data,
                    foundationEncoding: .utf16LittleEndian,
                    encoding: .utf16LittleEndian(hasByteOrderMark: false),
                    url: url
                )
            case .big:
                return try decodeUTF16(
                    data,
                    foundationEncoding: .utf16BigEndian,
                    encoding: .utf16BigEndian(hasByteOrderMark: false),
                    url: url
                )
            }
        }

        if data.contains(0) {
            throw TextFileEditingError.binaryFile(url)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw TextFileEditingError.invalidTextEncoding(url)
        }
        try rejectBinaryText(text, url: url)
        return (text, .utf8(hasByteOrderMark: false))
    }

    private enum UTF16Endian {
        case little
        case big
    }

    /// BOM-less UTF-16 is accepted only when null-byte placement makes the
    /// byte order unambiguous. This avoids treating arbitrary binary data as
    /// editable text.
    private nonisolated static func inferredUTF16Endian(from data: Data) -> UTF16Endian? {
        guard data.count >= 4, data.count.isMultiple(of: 2) else {
            return nil
        }

        let sampleCount = min(data.count, 4_096)
        let evenSampleCount = sampleCount - (sampleCount % 2)
        var evenNulls = 0
        var oddNulls = 0
        var pairCount = 0
        var index = 0
        while index < evenSampleCount {
            if data[index] == 0 { evenNulls += 1 }
            if data[index + 1] == 0 { oddNulls += 1 }
            pairCount += 1
            index += 2
        }

        guard pairCount > 0 else { return nil }
        let likelyNullThreshold = max(1, pairCount * 3 / 10)
        let unlikelyNullThreshold = pairCount / 20

        if oddNulls >= likelyNullThreshold, evenNulls <= unlikelyNullThreshold {
            return .little
        }
        if evenNulls >= likelyNullThreshold, oddNulls <= unlikelyNullThreshold {
            return .big
        }
        return nil
    }

    private nonisolated static func decodeUTF16(
        _ data: Data,
        foundationEncoding: String.Encoding,
        encoding: TextFileEncoding,
        url: URL
    ) throws -> (text: String, encoding: TextFileEncoding) {
        guard data.count.isMultiple(of: 2),
              let text = String(data: data, encoding: foundationEncoding) else {
            throw TextFileEditingError.invalidTextEncoding(url)
        }
        try rejectBinaryText(text, url: url)
        return (text, encoding)
    }

    private nonisolated static func rejectBinaryText(_ text: String, url: URL) throws {
        if text.unicodeScalars.contains(where: { scalar in
            let value = scalar.value
            return value < 0x20 && value != 0x09 && value != 0x0A
                && value != 0x0C && value != 0x0D
        }) {
            throw TextFileEditingError.binaryFile(url)
        }
    }

    private nonisolated static func encode(
        _ text: String,
        as encoding: TextFileEncoding,
        url: URL
    ) throws -> Data {
        let stringEncoding: String.Encoding
        let byteOrderMark: Data

        switch encoding {
        case .utf8(let hasByteOrderMark):
            stringEncoding = .utf8
            byteOrderMark = hasByteOrderMark ? utf8ByteOrderMark : Data()
        case .utf16LittleEndian(let hasByteOrderMark):
            stringEncoding = .utf16LittleEndian
            byteOrderMark = hasByteOrderMark ? utf16LittleEndianByteOrderMark : Data()
        case .utf16BigEndian(let hasByteOrderMark):
            stringEncoding = .utf16BigEndian
            byteOrderMark = hasByteOrderMark ? utf16BigEndianByteOrderMark : Data()
        }

        guard let payload = text.data(using: stringEncoding, allowLossyConversion: false) else {
            throw TextFileEditingError.cannotEncode(url)
        }
        return byteOrderMark + payload
    }

    private nonisolated static func fingerprint(at url: URL) throws -> TextFileFingerprint {
        var fileStatus = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &fileStatus)
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard (fileStatus.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw TextFileEditingError.unsafeItem(url)
        }

        return TextFileFingerprint(
            deviceID: UInt64(fileStatus.st_dev),
            fileID: UInt64(fileStatus.st_ino),
            byteCount: Int64(fileStatus.st_size),
            modificationSeconds: Int64(fileStatus.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(fileStatus.st_mtimespec.tv_nsec)
        )
    }

    private nonisolated static func entryType(at url: URL) throws -> mode_t {
        var fileStatus = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &fileStatus)
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return fileStatus.st_mode & mode_t(S_IFMT)
    }

    private nonisolated static func uniqueStagingURL(
        beside originalURL: URL,
        fileSystem: any FileSystemOperating
    ) -> URL {
        let directoryURL = originalURL.deletingLastPathComponent()
        var stagingURL: URL
        repeat {
            stagingURL = directoryURL.appendingPathComponent(
                ".openpane-edit-\(UUID().uuidString)",
                isDirectory: false
            )
        } while fileSystem.fileExists(at: stagingURL)
        return stagingURL
    }

    private nonisolated static func isDestinationExistsError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EEXIST) {
            return true
        }
        return error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.fileWriteFileExists.rawValue
    }

    private nonisolated static func userReadableReason(for error: Error) -> String {
        let description = (error as NSError).localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? "The operation failed." : description
    }
}
