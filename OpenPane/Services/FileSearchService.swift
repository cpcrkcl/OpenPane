//
//  FileSearchService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import Foundation

nonisolated protocol FileSearchServicing: Sendable {
    nonisolated func search(
        root: URL,
        query: String,
        includeHiddenFiles: Bool,
        limit: Int
    ) async throws -> [FileItem]
}

nonisolated struct FileSearchService: FileSearchServicing {
    static let defaultLimit = 500

    nonisolated func search(
        root: URL,
        query: String,
        includeHiddenFiles: Bool,
        limit: Int = Self.defaultLimit
    ) async throws -> [FileItem] {
        try await Task.detached(priority: .userInitiated) {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedQuery.isEmpty, limit > 0 else {
                return []
            }

            do {
                try Self.validateDirectory(root)

                let options: FileManager.DirectoryEnumerationOptions = includeHiddenFiles ? [] : [.skipsHiddenFiles]
                var enumerationError: Error?

                guard let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: Array(FileItem.resourceKeys),
                    options: options,
                    errorHandler: { _, error in
                        enumerationError = error
                        return false
                    }
                ) else {
                    throw FileBrowserError.unreadableDirectory(root, "The folder could not be searched.")
                }

                var results: [FileItem] = []

                while let itemURL = enumerator.nextObject() as? URL {
                    let item = try FileItem(url: itemURL)

                    if !includeHiddenFiles && (item.isHidden || item.name.hasPrefix(".")) {
                        if item.isDirectory {
                            enumerator.skipDescendants()
                        }
                        continue
                    }

                    guard item.name.localizedCaseInsensitiveContains(trimmedQuery) else {
                        continue
                    }

                    results.append(item)

                    if results.count >= limit {
                        break
                    }
                }

                if let enumerationError {
                    throw enumerationError
                }

                return results.sorted(by: Self.sortItems)
            } catch let error as FileBrowserError {
                throw error
            } catch {
                if Self.isAccessDeniedError(error) {
                    throw FileBrowserError.accessDenied(root)
                }

                throw FileBrowserError.unreadableDirectory(root, Self.userReadableReason(for: error))
            }
        }.value
    }

    private nonisolated static func sortItems(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }

        let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
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

        return "The folder could not be searched."
    }
}
