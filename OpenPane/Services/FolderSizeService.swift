//
//  FolderSizeService.swift
//  OpenPane
//
//  Created by Codex on 7/3/26.
//

import Foundation

nonisolated struct FolderSizeResult: Equatable, Sendable {
    let byteCount: Int64
    let skippedItemCount: Int

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

nonisolated enum FolderSizeError: LocalizedError, Equatable, Sendable {
    case notDirectory(URL)

    var errorDescription: String? {
        switch self {
        case .notDirectory(let url):
            return "\(url.openPaneDisplayName) is not a folder."
        }
    }
}

nonisolated protocol FolderSizeServicing: Sendable {
    nonisolated func size(of folderURL: URL) async throws -> FolderSizeResult
    nonisolated func cachedSize(of folderURL: URL) -> FolderSizeResult?
    nonisolated func invalidate(_ folderURL: URL)
    nonisolated func invalidateDescendants(of directoryURL: URL)
}

nonisolated final class FolderSizeService: FolderSizeServicing, @unchecked Sendable {
    private struct CacheKey: Hashable {
        let url: URL
        let modificationTimestamp: TimeInterval?
    }

    private let lock = NSLock()
    private var cachedResultsByKey: [CacheKey: FolderSizeResult] = [:]

    nonisolated init() {}

    nonisolated func size(of folderURL: URL) async throws -> FolderSizeResult {
        try Task.checkCancellation()

        let cacheKey = try Self.cacheKey(for: folderURL)

        if let cachedResult = cachedResult(for: cacheKey) {
            return cachedResult
        }

        try Task.checkCancellation()

        let result = try await Self.calculateSize(of: folderURL)
        store(result, for: cacheKey)

        return result
    }

    nonisolated func cachedSize(of folderURL: URL) -> FolderSizeResult? {
        guard let cacheKey = try? Self.cacheKey(for: folderURL) else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        return cachedResultsByKey[cacheKey]
    }

    nonisolated func invalidate(_ folderURL: URL) {
        let standardizedURL = folderURL.standardizedFileURL

        lock.lock()
        cachedResultsByKey = cachedResultsByKey.filter {
            $0.key.url != standardizedURL
        }
        lock.unlock()
    }

    nonisolated func invalidateDescendants(of directoryURL: URL) {
        let standardizedDirectoryURL = directoryURL.standardizedFileURL

        lock.lock()
        cachedResultsByKey = cachedResultsByKey.filter {
            let cachedURL = $0.key.url
            return cachedURL != standardizedDirectoryURL &&
                !cachedURL.isDescendant(of: standardizedDirectoryURL)
        }
        lock.unlock()
    }

    private nonisolated static func calculateSize(of folderURL: URL) async throws -> FolderSizeResult {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw FolderSizeError.notDirectory(folderURL)
            }

            let resourceKeys: [URLResourceKey] = [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .fileResourceIdentifierKey,
                .volumeIdentifierKey
            ]
            var skippedItemCount = 0
            var byteCount: Int64 = 0
            var visitedDirectoryIDs: Set<FileResourceIdentity> = []

            if let rootIdentity = fileResourceIdentity(for: folderURL) {
                visitedDirectoryIDs.insert(rootIdentity)
            }

            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in
                    skippedItemCount += 1
                    return true
                }
            ) else {
                return FolderSizeResult(byteCount: 0, skippedItemCount: 1)
            }

            while let itemURL = enumerator.nextObject() as? URL {
                try Task.checkCancellation()

                do {
                    let values = try itemURL.resourceValues(forKeys: Set(resourceKeys))

                    if values.isSymbolicLink == true {
                        if values.isDirectory == true {
                            enumerator.skipDescendants()
                        }
                        continue
                    }

                    if values.isDirectory == true {
                        if let identity = fileResourceIdentity(from: values),
                           !visitedDirectoryIDs.insert(identity).inserted {
                            enumerator.skipDescendants()
                        }
                        continue
                    }

                    if let fileSize = values.fileSize {
                        byteCount += Int64(fileSize)
                    } else if let allocatedSize = values.totalFileAllocatedSize {
                        byteCount += Int64(allocatedSize)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    skippedItemCount += 1
                }
            }

            return FolderSizeResult(byteCount: byteCount, skippedItemCount: skippedItemCount)
        }.value
    }

    private nonisolated static func cacheKey(for url: URL) throws -> CacheKey {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FolderSizeError.notDirectory(url)
        }

        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return CacheKey(
            url: url.standardizedFileURL,
            modificationTimestamp: values?.contentModificationDate?.timeIntervalSince1970
        )
    }

    private nonisolated static func fileResourceIdentity(for url: URL) -> FileResourceIdentity? {
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey]) else {
            return nil
        }

        return fileResourceIdentity(from: values)
    }

    private nonisolated static func fileResourceIdentity(from values: URLResourceValues) -> FileResourceIdentity? {
        guard let fileIdentifier = values.fileResourceIdentifier as? NSObject,
              let volumeIdentifier = values.volumeIdentifier as? NSObject else {
            return nil
        }

        return FileResourceIdentity(
            fileIdentifier: String(describing: fileIdentifier),
            volumeIdentifier: String(describing: volumeIdentifier)
        )
    }

    private nonisolated func cachedResult(for cacheKey: CacheKey) -> FolderSizeResult? {
        lock.lock()
        defer { lock.unlock() }

        return cachedResultsByKey[cacheKey]
    }

    private nonisolated func store(_ result: FolderSizeResult, for cacheKey: CacheKey) {
        lock.lock()
        cachedResultsByKey[cacheKey] = result
        lock.unlock()
    }
}

private nonisolated struct FileResourceIdentity: Hashable {
    let fileIdentifier: String
    let volumeIdentifier: String
}
