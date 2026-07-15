//
//  FileBrowserService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation

enum FileBrowserError: LocalizedError, Equatable, Sendable {
    case directoryNotFound(URL)
    case notDirectory(URL)
    case accessDenied(URL)
    case unreadableDirectory(URL, String)

    var errorDescription: String? {
        switch self {
        case .directoryNotFound(let url):
            return "\(Self.displayName(for: url)) could not be found."
        case .notDirectory(let url):
            return "\(Self.displayName(for: url)) is not a folder."
        case .accessDenied(let url):
            return "You do not have permission to open \(Self.displayName(for: url))."
        case .unreadableDirectory(let url, let reason):
            return "Could not open \(Self.displayName(for: url)): \(reason)"
        }
    }

    private static func displayName(for url: URL) -> String {
        url.openPaneDisplayName
    }
}

nonisolated protocol FileBrowserServicing: Sendable {
    nonisolated func contentsOfDirectory(at url: URL, includeHiddenFiles: Bool) async throws -> [FileItem]
    nonisolated func directorySnapshot(
        at url: URL,
        includeHiddenFiles: Bool,
        includeFingerprint: Bool,
        priority: TaskPriority
    ) async throws -> DirectorySnapshot
}

/// Constant-size, order-independent signature over the presented entries.
/// Count plus two commutative 64-bit accumulators keeps monitor comparison O(n)
/// without retaining or sorting a second directory-sized array. Entry content
/// modification dates are included so a directory monitor event caused by an
/// in-place edit does not leave the size and modified columns stale.
nonisolated struct DirectoryFingerprint: Equatable, Sendable {
    let entryCount: Int
    let entryHashXOR: UInt64
    let entryHashSum: UInt64
    let directoryModificationDate: Date?

    init(
        items: [FileItem],
        directoryModificationDate: Date? = nil,
        entryModificationDates: [Date?] = []
    ) {
        var hashXOR: UInt64 = 0
        var hashSum: UInt64 = 0
        for (index, item) in items.enumerated() {
            let modificationDate = entryModificationDates.indices.contains(index)
                ? entryModificationDates[index]
                : nil
            let entryHash = Self.stableEntryHash(for: item, modificationDate: modificationDate)
            hashXOR ^= entryHash
            hashSum &+= entryHash
        }

        entryCount = items.count
        entryHashXOR = hashXOR
        entryHashSum = hashSum
        self.directoryModificationDate = directoryModificationDate
    }

    private static func stableEntryHash(for item: FileItem, modificationDate: Date?) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in item.url.path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        hash ^= item.isDirectory ? 0xD1 : 0xF1
        hash &*= 1_099_511_628_211
        hash ^= item.isHidden ? 0xA1 : 0xB1
        hash &*= 1_099_511_628_211
        if let modificationDate {
            hash ^= modificationDate.timeIntervalSinceReferenceDate.bitPattern
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    static func includingDirectoryModificationDate(
        items: [FileItem],
        directoryURL: URL
    ) async -> DirectoryFingerprint {
        let task = Task.detached(priority: .utility) {
            let directoryModificationDate = try? directoryURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            let entryModificationDates = items.map {
                try? $0.url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
            }
            return DirectoryFingerprint(
                items: items,
                directoryModificationDate: directoryModificationDate,
                entryModificationDates: entryModificationDates
            )
        }

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

nonisolated struct DirectorySnapshot: Sendable {
    let items: [FileItem]
    let fingerprint: DirectoryFingerprint?
}

extension FileBrowserServicing {
    nonisolated func directorySnapshot(
        at url: URL,
        includeHiddenFiles: Bool,
        includeFingerprint: Bool,
        priority: TaskPriority
    ) async throws -> DirectorySnapshot {
        let items = try await contentsOfDirectory(
            at: url,
            includeHiddenFiles: includeHiddenFiles
        )
        let fingerprint: DirectoryFingerprint?
        if includeFingerprint {
            fingerprint = await DirectoryFingerprint.includingDirectoryModificationDate(
                items: items,
                directoryURL: url
            )
        } else {
            fingerprint = nil
        }
        return DirectorySnapshot(items: items, fingerprint: fingerprint)
    }
}

nonisolated struct FileBrowserService: FileBrowserServicing {
    nonisolated func contentsOfDirectory(at url: URL, includeHiddenFiles: Bool) async throws -> [FileItem] {
        try await directorySnapshot(
            at: url,
            includeHiddenFiles: includeHiddenFiles,
            includeFingerprint: false,
            priority: .userInitiated
        ).items
    }

    nonisolated func directorySnapshot(
        at url: URL,
        includeHiddenFiles: Bool,
        includeFingerprint: Bool,
        priority: TaskPriority
    ) async throws -> DirectorySnapshot {
        let task = Task.detached(priority: priority) {
            do {
                try Task.checkCancellation()
                try Self.validateDirectory(url)
                try Task.checkCancellation()

                #if DEBUG
                PerformanceDiagnostics.shared.recordDirectoryEnumeration()
                #endif

                var resourceKeys = FileItem.essentialResourceKeys
                if includeFingerprint {
                    resourceKeys.insert(.contentModificationDateKey)
                }
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: []
                )

                var items: [FileItem] = []
                items.reserveCapacity(fileURLs.count)

                for fileURL in fileURLs {
                    try Task.checkCancellation()
                    let item = try FileItem(essentialURL: fileURL)

                    guard includeHiddenFiles || (!item.isHidden && !item.name.hasPrefix(".")) else {
                        continue
                    }

                    items.append(item)
                }

                try Task.checkCancellation()
                let fingerprint: DirectoryFingerprint?
                if includeFingerprint {
                    let directoryModificationDate = try? url.resourceValues(
                        forKeys: [.contentModificationDateKey]
                    ).contentModificationDate
                    var entryModificationDates: [Date?] = []
                    entryModificationDates.reserveCapacity(items.count)
                    for (index, item) in items.enumerated() {
                        if index.isMultiple(of: 128) {
                            try Task.checkCancellation()
                        }
                        entryModificationDates.append(
                            try? item.url.resourceValues(forKeys: [.contentModificationDateKey])
                                .contentModificationDate
                        )
                    }
                    fingerprint = DirectoryFingerprint(
                        items: items,
                        directoryModificationDate: directoryModificationDate,
                        entryModificationDates: entryModificationDates
                    )
                } else {
                    fingerprint = nil
                }
                return DirectorySnapshot(
                    items: items,
                    fingerprint: fingerprint
                )
            } catch let error as FileBrowserError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Self.isAccessDeniedError(error) {
                    throw FileBrowserError.accessDenied(url)
                }

                throw FileBrowserError.unreadableDirectory(url, Self.userReadableReason(for: error))
            }
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func validateDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FileBrowserError.directoryNotFound(url)
        }

        guard isDirectory.boolValue else {
            throw FileBrowserError.notDirectory(url)
        }
    }

    private nonisolated static func isAccessDeniedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError
    }

    private nonisolated static func userReadableReason(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        if isAccessDeniedError(error) {
            return "Permission denied."
        }

        return "The folder could not be read."
    }
}
