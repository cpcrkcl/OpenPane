//
//  FilePreviewMetadataService.swift
//  OpenPane
//
//  Metadata is loaded away from the main actor and cached by URL plus file
//  revision. The small deterministic LRU keeps selection scrubbing responsive
//  without retaining metadata for an unbounded number of files.
//

@preconcurrency import AVFoundation
import Foundation
@preconcurrency import ImageIO
@preconcurrency import PDFKit
import UniformTypeIdentifiers

nonisolated enum FilePreviewMetadataError: LocalizedError, Equatable, Sendable {
    case fileChangedDuringLoad(URL)

    var errorDescription: String? {
        switch self {
        case .fileChangedDuringLoad(let url):
            return "\(url.lastPathComponent) changed while its details were loading."
        }
    }
}

nonisolated protocol FilePreviewMetadataServicing: Sendable {
    nonisolated func metadata(for url: URL) async throws -> FilePreviewMetadata
    nonisolated func enrichedMetadata(for metadata: FilePreviewMetadata) async throws -> FilePreviewMetadata
    nonisolated func cachedMetadata(for url: URL, revision: FilePreviewRevision) -> FilePreviewMetadata?
    nonisolated func invalidate(_ url: URL)
}

extension FilePreviewMetadataServicing {
    nonisolated func enrichedMetadata(for metadata: FilePreviewMetadata) async throws -> FilePreviewMetadata {
        metadata
    }
}

typealias FilePreviewRevisionLoading = @Sendable (URL) async throws -> FilePreviewRevision
typealias FilePreviewMetadataLoading = @Sendable (URL, FilePreviewRevision) async throws -> FilePreviewMetadata

nonisolated final class FilePreviewMetadataService: FilePreviewMetadataServicing, @unchecked Sendable {
    private struct CacheKey: Hashable {
        let url: URL
        let revision: FilePreviewRevision
    }

    private let lock = NSLock()
    private let maximumCacheEntryCount: Int
    private let revisionLoader: FilePreviewRevisionLoading
    private let metadataLoader: FilePreviewMetadataLoading
    private var cachedMetadataByKey: [CacheKey: FilePreviewMetadata] = [:]
    private var cacheKeysInRecencyOrder: [CacheKey] = []

    #if DEBUG
    nonisolated var cachedMetadataCount: Int {
        lock.withLock { cachedMetadataByKey.count }
    }
    #endif

    nonisolated init(
        maximumCacheEntryCount: Int = 64,
        revisionLoader: @escaping FilePreviewRevisionLoading = FilePreviewMetadataService.loadRevision,
        metadataLoader: @escaping FilePreviewMetadataLoading = FilePreviewMetadataService.loadMetadata
    ) {
        self.maximumCacheEntryCount = max(1, maximumCacheEntryCount)
        self.revisionLoader = revisionLoader
        self.metadataLoader = metadataLoader
    }

    nonisolated func metadata(for url: URL) async throws -> FilePreviewMetadata {
        try Task.checkCancellation()
        let standardizedURL = url.standardizedFileURL
        let revision = try await revisionLoader(standardizedURL)
        try Task.checkCancellation()

        if let cachedMetadata = cachedMetadata(for: standardizedURL, revision: revision) {
            return cachedMetadata
        }

        let loadedMetadata = try await metadataLoader(standardizedURL, revision)
        try Task.checkCancellation()

        // Do not publish or cache a snapshot that became stale while format
        // details (notably network media metadata) were being loaded.
        let currentRevision = try await revisionLoader(standardizedURL)
        try Task.checkCancellation()
        guard currentRevision == revision else {
            throw FilePreviewMetadataError.fileChangedDuringLoad(standardizedURL)
        }

        insert(loadedMetadata, for: CacheKey(url: standardizedURL, revision: revision))
        return loadedMetadata
    }

    nonisolated func enrichedMetadata(for metadata: FilePreviewMetadata) async throws -> FilePreviewMetadata {
        guard metadata.formatDetails == nil,
              let typeIdentifier = metadata.typeIdentifier,
              let contentType = UTType(typeIdentifier) else {
            return metadata
        }

        let formatDetails: FileFormatDetails?
        if contentType.conforms(to: .movie) {
            guard VideoPreviewPolicy.shouldInspectFormat(
                typeIdentifier: metadata.typeIdentifier,
                fileExtension: metadata.url.pathExtension,
                logicalSize: metadata.logicalSize
            ) else {
                return metadata
            }
            do {
                formatDetails = try await Self.loadVideoDetails(for: metadata.url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                formatDetails = .video(duration: nil, pixelWidth: nil, pixelHeight: nil)
            }
        } else if contentType.conforms(to: .audio) {
            do {
                formatDetails = try await Self.loadAudioDetails(for: metadata.url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                formatDetails = .audio(duration: nil)
            }
        } else {
            return metadata
        }

        try Task.checkCancellation()
        let currentRevision = try await revisionLoader(metadata.url)
        guard currentRevision == metadata.revision else {
            throw FilePreviewMetadataError.fileChangedDuringLoad(metadata.url)
        }

        let enrichedMetadata = metadata.replacingFormatDetails(formatDetails)
        insert(
            enrichedMetadata,
            for: CacheKey(url: metadata.url.standardizedFileURL, revision: metadata.revision)
        )
        return enrichedMetadata
    }

    nonisolated func cachedMetadata(for url: URL, revision: FilePreviewRevision) -> FilePreviewMetadata? {
        let key = CacheKey(url: url.standardizedFileURL, revision: revision)

        return lock.withLock {
            guard let metadata = cachedMetadataByKey[key] else {
                return nil
            }

            cacheKeysInRecencyOrder.removeAll { $0 == key }
            cacheKeysInRecencyOrder.append(key)
            return metadata
        }
    }

    nonisolated func invalidate(_ url: URL) {
        let standardizedURL = url.standardizedFileURL

        lock.withLock {
            let matchingKeys = cachedMetadataByKey.keys.filter { $0.url == standardizedURL }
            matchingKeys.forEach { cachedMetadataByKey[$0] = nil }
            cacheKeysInRecencyOrder.removeAll { $0.url == standardizedURL }
        }
    }

    private nonisolated func insert(_ metadata: FilePreviewMetadata, for key: CacheKey) {
        lock.withLock {
            // An older revision of the same path can no longer be useful and
            // should not consume one of the 64 bounded entries.
            let supersededKeys = cachedMetadataByKey.keys.filter { $0.url == key.url && $0 != key }
            supersededKeys.forEach { cachedMetadataByKey[$0] = nil }
            cacheKeysInRecencyOrder.removeAll { $0.url == key.url }

            cachedMetadataByKey[key] = metadata
            cacheKeysInRecencyOrder.append(key)

            while cachedMetadataByKey.count > maximumCacheEntryCount,
                  let leastRecentKey = cacheKeysInRecencyOrder.first {
                cachedMetadataByKey[leastRecentKey] = nil
                cacheKeysInRecencyOrder.removeFirst()
            }
        }
    }

    private nonisolated static func loadRevision(for url: URL) async throws -> FilePreviewRevision {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [
                .fileResourceIdentifierKey,
                .volumeIdentifierKey,
                .fileSizeKey,
                .contentModificationDateKey
            ])
            try Task.checkCancellation()

            return FilePreviewRevision(
                resourceIdentifier: resourceIdentifier(from: values),
                logicalSize: values.fileSize.map(Int64.init),
                contentModificationDate: values.contentModificationDate
            )
        }.value
    }

    private nonisolated static func loadMetadata(
        for url: URL,
        revision: FilePreviewRevision
    ) async throws -> FilePreviewMetadata {
        let core = try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try loadCoreMetadata(for: url, revision: revision)
        }.value

        try Task.checkCancellation()

        try Task.checkCancellation()
        return core.metadata(formatDetails: core.synchronousFormatDetails)
    }
}

private extension FilePreviewMetadataService {
    nonisolated struct CoreMetadata: Sendable {
        let url: URL
        let revision: FilePreviewRevision
        let name: String
        let kindDescription: String
        let fileExtension: String?
        let typeIdentifier: String?
        let mimeType: String?
        let parentPath: String
        let volumeName: String?
        let volumeKind: FilePreviewVolumeKind
        let symbolicLinkTarget: String?
        let creationDate: Date?
        let contentModificationDate: Date?
        let attributeModificationDate: Date?
        let contentAccessDate: Date?
        let addedToDirectoryDate: Date?
        let logicalSize: Int64?
        let allocatedSize: Int64?
        let ownerAccountName: String?
        let groupOwnerAccountName: String?
        let posixPermissions: Int?
        let isReadable: Bool?
        let isWritable: Bool?
        let isExecutable: Bool?
        let finderTags: [String]
        let isDirectory: Bool
        let isPackage: Bool
        let isSymbolicLink: Bool
        let contentType: UTType?
        let synchronousFormatDetails: FileFormatDetails?

        nonisolated func metadata(formatDetails: FileFormatDetails?) -> FilePreviewMetadata {
            FilePreviewMetadata(
                url: url,
                revision: revision,
                name: name,
                kindDescription: kindDescription,
                fileExtension: fileExtension,
                typeIdentifier: typeIdentifier,
                mimeType: mimeType,
                fullPath: url.path,
                parentPath: parentPath,
                volumeName: volumeName,
                volumeKind: volumeKind,
                symbolicLinkTarget: symbolicLinkTarget,
                creationDate: creationDate,
                contentModificationDate: contentModificationDate,
                attributeModificationDate: attributeModificationDate,
                contentAccessDate: contentAccessDate,
                addedToDirectoryDate: addedToDirectoryDate,
                logicalSize: logicalSize,
                allocatedSize: allocatedSize,
                ownerAccountName: ownerAccountName,
                groupOwnerAccountName: groupOwnerAccountName,
                posixPermissions: posixPermissions,
                isReadable: isReadable,
                isWritable: isWritable,
                isExecutable: isExecutable,
                finderTags: finderTags,
                isDirectory: isDirectory,
                isPackage: isPackage,
                isSymbolicLink: isSymbolicLink,
                formatDetails: formatDetails
            )
        }
    }

    nonisolated static func loadCoreMetadata(
        for url: URL,
        revision: FilePreviewRevision
    ) throws -> CoreMetadata {
        let keys: Set<URLResourceKey> = [
            .localizedNameKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .creationDateKey,
            .contentAccessDateKey,
            .contentModificationDateKey,
            .attributeModificationDateKey,
            .addedToDirectoryDateKey,
            .typeIdentifierKey,
            .localizedTypeDescriptionKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .isReadableKey,
            .isWritableKey,
            .isExecutableKey,
            .tagNamesKey,
            .volumeNameKey,
            .volumeIsLocalKey
        ]
        let values = try url.resourceValues(forKeys: keys)
        try Task.checkCancellation()

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let typeIdentifier = values.typeIdentifier
        let contentType = typeIdentifier.flatMap(UTType.init)
        let isDirectory = values.isDirectory ?? false
        let isPackage = values.isPackage ?? false
        let isSymbolicLink = values.isSymbolicLink ?? false
        let fileExtension = url.pathExtension.isEmpty ? nil : url.pathExtension
        let logicalSize = isDirectory ? nil : values.fileSize.map(Int64.init)
        let allocatedSize = isDirectory ? nil : values.totalFileAllocatedSize.map(Int64.init)
        let volumeKind: FilePreviewVolumeKind = switch values.volumeIsLocal {
        case true: .local
        case false: .network
        case nil: .unknown
        }

        let synchronousFormatDetails = synchronousFormatDetails(
            for: url,
            contentType: contentType,
            isPackage: isPackage
        )

        return CoreMetadata(
            url: url,
            revision: revision,
            name: values.localizedName ?? url.lastPathComponent,
            kindDescription: values.localizedTypeDescription
                ?? contentType?.localizedDescription
                ?? (isDirectory ? "Folder" : "File"),
            fileExtension: fileExtension,
            typeIdentifier: typeIdentifier,
            mimeType: contentType?.preferredMIMEType,
            parentPath: url.deletingLastPathComponent().path,
            volumeName: values.volumeName,
            volumeKind: volumeKind,
            symbolicLinkTarget: isSymbolicLink
                ? try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                : nil,
            creationDate: values.creationDate ?? attributes?[.creationDate] as? Date,
            contentModificationDate: values.contentModificationDate ?? attributes?[.modificationDate] as? Date,
            attributeModificationDate: values.attributeModificationDate,
            contentAccessDate: values.contentAccessDate,
            addedToDirectoryDate: values.addedToDirectoryDate,
            logicalSize: logicalSize,
            allocatedSize: allocatedSize,
            ownerAccountName: attributes?[.ownerAccountName] as? String,
            groupOwnerAccountName: attributes?[.groupOwnerAccountName] as? String,
            posixPermissions: attributes?[.posixPermissions] as? Int,
            isReadable: values.isReadable,
            isWritable: values.isWritable,
            isExecutable: values.isExecutable,
            finderTags: values.tagNames ?? [],
            isDirectory: isDirectory,
            isPackage: isPackage,
            isSymbolicLink: isSymbolicLink,
            contentType: contentType,
            synchronousFormatDetails: synchronousFormatDetails
        )
    }

    nonisolated static func synchronousFormatDetails(
        for url: URL,
        contentType: UTType?,
        isPackage: Bool
    ) -> FileFormatDetails? {
        if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame ||
            contentType?.conforms(to: .applicationBundle) == true {
            let bundle = Bundle(url: url)
            return .application(
                bundleIdentifier: bundle?.bundleIdentifier,
                shortVersion: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                buildVersion: bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            )
        }

        guard !isPackage else {
            return nil
        }

        if contentType?.conforms(to: .image) == true,
           let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
           let width = integerValue(properties[kCGImagePropertyPixelWidth]),
           let height = integerValue(properties[kCGImagePropertyPixelHeight]) {
            return .image(
                pixelWidth: width,
                pixelHeight: height,
                colorModel: properties[kCGImagePropertyColorModel] as? String
            )
        }

        if contentType?.conforms(to: .pdf) == true,
           let document = PDFDocument(url: url) {
            return .pdf(pageCount: document.pageCount, isEncrypted: document.isEncrypted)
        }

        return nil
    }

    nonisolated static func loadAudioDetails(for url: URL) async throws -> FileFormatDetails {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        try Task.checkCancellation()
        return .audio(duration: duration.seconds.isFinite ? duration.seconds : nil)
    }

    nonisolated static func loadVideoDetails(for url: URL) async throws -> FileFormatDetails {
        let asset = AVURLAsset(url: url)
        async let durationValue = asset.load(.duration)
        async let videoTracks = asset.loadTracks(withMediaType: .video)

        let duration = try await durationValue
        let tracks = try await videoTracks
        try Task.checkCancellation()

        var pixelWidth: Int?
        var pixelHeight: Int?
        if let track = tracks.first {
            async let naturalSizeValue = track.load(.naturalSize)
            async let preferredTransformValue = track.load(.preferredTransform)
            let naturalSize = try await naturalSizeValue
            let preferredTransform = try await preferredTransformValue
            let transformedSize = naturalSize.applying(preferredTransform)
            pixelWidth = Int(abs(transformedSize.width).rounded())
            pixelHeight = Int(abs(transformedSize.height).rounded())
        }

        try Task.checkCancellation()
        return .video(
            duration: duration.seconds.isFinite ? duration.seconds : nil,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    nonisolated static func resourceIdentifier(from values: URLResourceValues) -> String? {
        let fileIdentifier = stableIdentifier(values.fileResourceIdentifier)
        let volumeIdentifier = stableIdentifier(values.volumeIdentifier)

        switch (volumeIdentifier, fileIdentifier) {
        case let (volume?, file?): return "\(volume):\(file)"
        case let (_, file?): return file
        case let (volume?, _): return volume
        case (nil, nil): return nil
        }
    }

    nonisolated static func stableIdentifier(_ value: Any?) -> String? {
        if let data = value as? Data {
            return data.base64EncodedString()
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return value.map(String.init(describing:))
    }

    nonisolated static func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return value as? Int
    }
}
