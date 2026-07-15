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
    private struct CacheEntry {
        let result: FolderSizeResult
        let insertionUptime: TimeInterval
    }

    private let lock = NSLock()
    private let maximumCacheEntryCount: Int
    private let cacheTTL: TimeInterval
    private var cachedResultsByURL: [URL: CacheEntry] = [:]
    private var cacheURLsInRecencyOrder: [URL] = []

    #if DEBUG
    nonisolated var cachedResultCount: Int {
        lock.withLock { cachedResultsByURL.count }
    }
    #endif

    /// Cache key: standardized folder URL. Results expire after 30 seconds by
    /// default, are explicitly invalidated after OpenPane operations, and use
    /// LRU eviction above 128 entries. Cache reads never touch the filesystem.
    nonisolated init(
        maximumCacheEntryCount: Int = 128,
        cacheTTL: TimeInterval = 30
    ) {
        self.maximumCacheEntryCount = max(1, maximumCacheEntryCount)
        self.cacheTTL = max(0, cacheTTL)
    }

    nonisolated func size(of folderURL: URL) async throws -> FolderSizeResult {
        try Task.checkCancellation()

        let standardizedURL = folderURL.standardizedFileURL

        if let cachedResult = cachedResult(for: standardizedURL) {
            return cachedResult
        }

        try Task.checkCancellation()

        let result = try await Self.calculateSize(of: folderURL)
        store(result, for: standardizedURL)

        return result
    }

    nonisolated func cachedSize(of folderURL: URL) -> FolderSizeResult? {
        cachedResult(for: folderURL.standardizedFileURL)
    }

    nonisolated func invalidate(_ folderURL: URL) {
        let standardizedURL = folderURL.standardizedFileURL

        lock.lock()
        cachedResultsByURL[standardizedURL] = nil
        cacheURLsInRecencyOrder.removeAll { $0 == standardizedURL }
        lock.unlock()
    }

    nonisolated func invalidateDescendants(of directoryURL: URL) {
        let standardizedDirectoryURL = directoryURL.standardizedFileURL

        lock.lock()
        let invalidatedURLs = cachedResultsByURL.keys.filter {
            $0 == standardizedDirectoryURL || $0.isDescendant(of: standardizedDirectoryURL)
        }
        invalidatedURLs.forEach { cachedResultsByURL[$0] = nil }
        cacheURLsInRecencyOrder.removeAll { invalidatedURLs.contains($0) }
        lock.unlock()
    }

    private nonisolated static func calculateSize(of folderURL: URL) async throws -> FolderSizeResult {
        let task = Task.detached(priority: .utility) {
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
                options: [],
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
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
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

    private nonisolated func cachedResult(for url: URL) -> FolderSizeResult? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cachedResultsByURL[url] else {
            return nil
        }

        guard ProcessInfo.processInfo.systemUptime - entry.insertionUptime <= cacheTTL else {
            cachedResultsByURL[url] = nil
            cacheURLsInRecencyOrder.removeAll { $0 == url }
            return nil
        }

        cacheURLsInRecencyOrder.removeAll { $0 == url }
        cacheURLsInRecencyOrder.append(url)
        return entry.result
    }

    private nonisolated func store(_ result: FolderSizeResult, for url: URL) {
        lock.lock()
        cachedResultsByURL[url] = CacheEntry(
            result: result,
            insertionUptime: ProcessInfo.processInfo.systemUptime
        )
        cacheURLsInRecencyOrder.removeAll { $0 == url }
        cacheURLsInRecencyOrder.append(url)

        while cachedResultsByURL.count > maximumCacheEntryCount,
              let leastRecentlyUsedURL = cacheURLsInRecencyOrder.first {
            cacheURLsInRecencyOrder.removeFirst()
            cachedResultsByURL[leastRecentlyUsedURL] = nil
        }
        lock.unlock()
    }
}

private nonisolated struct FileResourceIdentity: Hashable {
    let fileIdentifier: String
    let volumeIdentifier: String
}
