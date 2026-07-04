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
}

nonisolated struct FileBrowserService: FileBrowserServicing {
    nonisolated func contentsOfDirectory(at url: URL, includeHiddenFiles: Bool) async throws -> [FileItem] {
        let task = Task.detached(priority: .userInitiated) {
            do {
                try Task.checkCancellation()
                try Self.validateDirectory(url)
                try Task.checkCancellation()

                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: Array(FileItem.resourceKeys),
                    options: []
                )

                var items: [FileItem] = []
                items.reserveCapacity(fileURLs.count)

                for fileURL in fileURLs {
                    try Task.checkCancellation()
                    let item = try FileItem(url: fileURL)

                    guard includeHiddenFiles || (!item.isHidden && !item.name.hasPrefix(".")) else {
                        continue
                    }

                    items.append(item)
                }

                try Task.checkCancellation()
                return items.sorted(by: Self.sortItems)
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

    private nonisolated static func sortItems(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
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
