//
//  TextFileEditingServiceTests.swift
//  OpenPaneTests
//

import Darwin
import Foundation
import Testing
@testable import OpenPane

struct TextFileEditingServiceTests {
    @Test func utf8BOMRoundTripsAndPreservesMetadata() async throws {
        let temporaryDirectory = try TextEditTestDirectory()
        let fileURL = temporaryDirectory.fileURL(named: "notes.txt")
        let originalData = Data([0xEF, 0xBB, 0xBF]) + Data("hello 🌎".utf8)
        try originalData.write(to: fileURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o640],
            ofItemAtPath: fileURL.path
        )
        try setExtendedAttribute(
            named: "com.openpane.text-edit-test",
            data: Data("kept".utf8),
            at: fileURL
        )

        let service = TextFileEditingService()
        let document = try await service.load(url: fileURL)

        #expect(document.text == "hello 🌎")
        #expect(document.encoding == .utf8(hasByteOrderMark: true))

        let saved = try await service.save(document: document, text: "updated 🌙")
        let savedData = try Data(contentsOf: fileURL)
        let savedAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

        #expect(saved.text == "updated 🌙")
        #expect(saved.fingerprint != document.fingerprint)
        #expect(savedData.starts(with: Data([0xEF, 0xBB, 0xBF])))
        #expect(String(data: savedData.dropFirst(3), encoding: .utf8) == "updated 🌙")
        #expect(savedAttributes[.posixPermissions] as? Int == 0o640)
        #expect(
            try extendedAttribute(named: "com.openpane.text-edit-test", at: fileURL) ==
                Data("kept".utf8)
        )
        #expect(try temporaryDirectory.stagingURLs().isEmpty)
    }

    @Test(arguments: [
        TextEncodingFixture(
            encoding: .utf16LittleEndian(hasByteOrderMark: true),
            dataEncoding: .utf16LittleEndian,
            byteOrderMark: Data([0xFF, 0xFE])
        ),
        TextEncodingFixture(
            encoding: .utf16BigEndian(hasByteOrderMark: true),
            dataEncoding: .utf16BigEndian,
            byteOrderMark: Data([0xFE, 0xFF])
        ),
        TextEncodingFixture(
            encoding: .utf16LittleEndian(hasByteOrderMark: false),
            dataEncoding: .utf16LittleEndian,
            byteOrderMark: Data()
        ),
        TextEncodingFixture(
            encoding: .utf16BigEndian(hasByteOrderMark: false),
            dataEncoding: .utf16BigEndian,
            byteOrderMark: Data()
        )
    ])
    func utf16EndianAndBOMRoundTrip(fixture: TextEncodingFixture) async throws {
        let temporaryDirectory = try TextEditTestDirectory()
        let fileURL = temporaryDirectory.fileURL(named: "unicode.txt")
        let originalText = "Alpha and café"
        let originalPayload = try #require(
            originalText.data(using: fixture.dataEncoding, allowLossyConversion: false)
        )
        try (fixture.byteOrderMark + originalPayload).write(to: fileURL)

        let service = TextFileEditingService()
        let document = try await service.load(url: fileURL)
        #expect(document.text == originalText)
        #expect(document.encoding == fixture.encoding)

        _ = try await service.save(document: document, text: "Beta and résumé")
        let savedData = try Data(contentsOf: fileURL)
        #expect(savedData.starts(with: fixture.byteOrderMark))
        let payload = fixture.byteOrderMark.isEmpty
            ? savedData
            : Data(savedData.dropFirst(fixture.byteOrderMark.count))
        #expect(String(data: payload, encoding: fixture.dataEncoding) == "Beta and résumé")
    }

    @Test func readsTextAcrossMultiple64KiBChunks() async throws {
        let temporaryDirectory = try TextEditTestDirectory()
        let fileURL = temporaryDirectory.fileURL(named: "large.txt")
        let text = String(repeating: "0123456789abcdef", count: 12_000)
        try Data(text.utf8).write(to: fileURL)

        let document = try await TextFileEditingService().load(url: fileURL)

        #expect(document.text == text)
    }

    @Test func rejectsFilesLargerThanTenMiB() async throws {
        let temporaryDirectory = try TextEditTestDirectory()
        let fileURL = temporaryDirectory.fileURL(named: "large.txt")
        try Data(
            repeating: UInt8(ascii: "a"),
            count: Int(TextFileEditingService.maximumEditableByteCount) + 1
        ).write(to: fileURL)

        let eligibility = await TextFileEditingService().inspect(url: fileURL)

        #expect(
            eligibility == .tooLarge(
                byteCount: TextFileEditingService.maximumEditableByteCount + 1,
                limit: TextFileEditingService.maximumEditableByteCount
            )
        )
    }

    @Test func rejectsBinaryAndMalformedText() async throws {
        let temporaryDirectory = try TextEditTestDirectory()
        let binaryURL = temporaryDirectory.fileURL(named: "binary.txt")
        let malformedURL = temporaryDirectory.fileURL(named: "malformed.txt")
        try Data([0x41, 0x00, 0x42]).write(to: binaryURL)
        try Data([0x41, 0xFF, 0x42]).write(to: malformedURL)
        let service = TextFileEditingService()

        await #expect(throws: TextFileEditingError.binaryFile(binaryURL)) {
            try await service.load(url: binaryURL)
        }
        await #expect(throws: TextFileEditingError.invalidTextEncoding(malformedURL)) {
            try await service.load(url: malformedURL)
        }
    }

    @Test func symbolicLinksAndPackagesCannotBeEdited() async throws {
        let temporaryDirectory = try TextEditTestDirectory()
        let targetURL = temporaryDirectory.fileURL(named: "target.txt")
        let linkURL = temporaryDirectory.fileURL(named: "link.txt")
        try "target".write(to: targetURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        let packageURL = temporaryDirectory.fileURL(named: "Example.app")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: false)

        let service = TextFileEditingService()
        #expect(await service.inspect(url: linkURL) == .symbolicLink)
        #expect(await service.inspect(url: packageURL) == .package)
    }

    @Test func externalModificationPreventsSaveAndPreservesBothVersions() async throws {
        let temporaryDirectory = try TextEditTestDirectory()
        let fileURL = temporaryDirectory.fileURL(named: "conflict.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        let service = TextFileEditingService()
        let document = try await service.load(url: fileURL)

        try "external version with a different size".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        await #expect(throws: TextFileEditingError.fileChanged(fileURL)) {
            try await service.save(document: document, text: "draft")
        }
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "external version with a different size")
        #expect(try temporaryDirectory.stagingURLs().isEmpty)
    }

    @Test func explicitOverwritePublishesDraftAfterExternalModification() async throws {
        let temporaryDirectory = try TextEditTestDirectory()
        let fileURL = temporaryDirectory.fileURL(named: "overwrite.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        let service = TextFileEditingService()
        let document = try await service.load(url: fileURL)
        try "external".write(to: fileURL, atomically: true, encoding: .utf8)

        _ = try await service.save(
            document: document,
            text: "intentional draft",
            conflictPolicy: .overwrite
        )

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "intentional draft")
        #expect(try temporaryDirectory.stagingURLs().isEmpty)
    }

    @Test func failedTransferCleansOnlyItsPartialStagingFile() async throws {
        let temporaryDirectory = try TextEditTestDirectory()
        let fileURL = temporaryDirectory.fileURL(named: "failure.txt")
        let unrelatedHiddenURL = temporaryDirectory.fileURL(named: ".openpane-edit-unrelated")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        try "leave me".write(to: unrelatedHiddenURL, atomically: true, encoding: .utf8)
        let document = try await TextFileEditingService().load(url: fileURL)
        let service = TextFileEditingService(transferService: PartialFailingTextTransfer())

        await #expect(throws: TextFileEditingError.self) {
            try await service.save(document: document, text: "draft")
        }

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "original")
        #expect(try String(contentsOf: unrelatedHiddenURL, encoding: .utf8) == "leave me")
        #expect(
            try temporaryDirectory.stagingURLs().map(\.lastPathComponent) ==
                [unrelatedHiddenURL.lastPathComponent]
        )
    }

    @Test func failedAtomicReplacementRemovesOwnedStagingAndPreservesOriginal() async throws {
        let temporaryDirectory = try TextEditTestDirectory()
        let fileURL = temporaryDirectory.fileURL(named: "publish-failure.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        let document = try await TextFileEditingService().load(url: fileURL)
        let service = TextFileEditingService(fileSystem: ReplaceFailingTextFileSystem())

        await #expect(throws: TextFileEditingError.self) {
            try await service.save(document: document, text: "draft")
        }

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "original")
        #expect(try temporaryDirectory.stagingURLs().isEmpty)
    }
}

struct TextEncodingFixture: CustomTestStringConvertible, Sendable {
    let encoding: TextFileEncoding
    let dataEncoding: String.Encoding
    let byteOrderMark: Data

    var testDescription: String {
        "\(encoding.displayName), BOM: \(encoding.hasByteOrderMark)"
    }
}

private final class TextEditTestDirectory: @unchecked Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneTextEditingTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func fileURL(named name: String) -> URL {
        url.appendingPathComponent(name)
    }

    func stagingURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".openpane-edit-") }
    }
}

private struct PartialFailingTextTransfer: FileTransferServicing {
    func copyItem(
        at sourceURL: URL,
        to destinationURL: URL,
        progressHandler: @escaping @Sendable (Int64) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws {
        try Data("partial".utf8).write(to: destinationURL)
        throw NSError(
            domain: "OpenPaneTextEditingTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Simulated transfer failure"]
        )
    }
}

private struct ReplaceFailingTextFileSystem: FileSystemOperating {
    private let base = FileManagerFileSystem()

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try base.copyItem(at: sourceURL, to: destinationURL)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try base.moveItem(at: sourceURL, to: destinationURL)
    }

    func moveItemExclusively(at sourceURL: URL, to destinationURL: URL) throws {
        try base.moveItemExclusively(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        try base.removeItem(at: url)
    }

    func replaceItem(at originalURL: URL, withItemAt replacementURL: URL) throws {
        throw NSError(
            domain: "OpenPaneTextEditingTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Simulated publish failure"]
        )
    }

    func fileExists(at url: URL) -> Bool {
        base.fileExists(at: url)
    }

    func fileExists(at url: URL, isDirectory: inout ObjCBool) -> Bool {
        base.fileExists(at: url, isDirectory: &isDirectory)
    }

    func isWritableFile(at url: URL) -> Bool {
        base.isWritableFile(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try base.contentsOfDirectory(at: url)
    }

    func createDirectory(at url: URL) throws {
        try base.createDirectory(at: url)
    }

    func createFile(at url: URL) -> Bool {
        base.createFile(at: url)
    }
}

private func setExtendedAttribute(named name: String, data: Data, at url: URL) throws {
    let result = data.withUnsafeBytes { buffer in
        setxattr(url.path, name, buffer.baseAddress, buffer.count, 0, 0)
    }
    guard result == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private func extendedAttribute(named name: String, at url: URL) throws -> Data {
    let size = getxattr(url.path, name, nil, 0, 0, 0)
    guard size >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    var data = Data(count: size)
    let readSize = data.withUnsafeMutableBytes { buffer in
        getxattr(url.path, name, buffer.baseAddress, buffer.count, 0, 0)
    }
    guard readSize == size else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return data
}
