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

typealias FileSearchItemBuilder = @Sendable (URL) throws -> FileItem

nonisolated struct FileSearchService: FileSearchServicing {
    static let defaultLimit = 500
    private let itemBuilder: FileSearchItemBuilder

    nonisolated init(
        itemBuilder: @escaping FileSearchItemBuilder = FileSearchService.makeFileItem
    ) {
        self.itemBuilder = itemBuilder
    }

    nonisolated func search(
        root: URL,
        query: String,
        includeHiddenFiles: Bool,
        limit: Int = Self.defaultLimit
    ) async throws -> [FileItem] {
        let itemBuilder = itemBuilder
        return try await Self.runSearch {
            try Task.checkCancellation()
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedQuery.isEmpty, limit > 0 else {
                return []
            }

            do {
                try Self.validateDirectory(root)

                let options: FileManager.DirectoryEnumerationOptions = includeHiddenFiles ? [] : [.skipsHiddenFiles]
                let displayRoot = root.standardizedFileURL
                let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
                let enumerationRoot = Self.isSymbolicLink(root) ? resolvedRoot : root

                guard let enumerator = FileManager.default.enumerator(
                    at: enumerationRoot,
                    includingPropertiesForKeys: Array(FileItem.essentialResourceKeys),
                    options: options,
                    errorHandler: { _, _ in
                        true
                    }
                ) else {
                    throw FileBrowserError.unreadableDirectory(root, "The folder could not be searched.")
                }

                var results: [FileItem] = []

                while let itemURL = enumerator.nextObject() as? URL {
                    try Task.checkCancellation()

                    do {
                        let essentialItem = try FileItem(essentialURL: itemURL)

                        if !includeHiddenFiles &&
                            (essentialItem.isHidden || essentialItem.name.hasPrefix(".")) {
                            if essentialItem.isDirectory {
                                enumerator.skipDescendants()
                            }
                            continue
                        }

                        guard essentialItem.name.localizedCaseInsensitiveContains(trimmedQuery) else {
                            continue
                        }

                        let resultURL = Self.url(
                            itemURL,
                            preservingRoot: root,
                            displayRoot: displayRoot,
                            resolvedRoot: resolvedRoot,
                            isDirectory: essentialItem.isDirectory
                        )
                        results.append(try itemBuilder(resultURL))

                        if results.count >= limit {
                            break
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        continue
                    }
                }

                return results
            } catch let error as FileBrowserError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Self.isAccessDeniedError(error) {
                    throw FileBrowserError.accessDenied(root)
                }

                throw FileBrowserError.unreadableDirectory(root, Self.userReadableReason(for: error))
            }
        }
    }

    private nonisolated static func runSearch<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let task = Task.detached(priority: .utility) {
            try operation()
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func url(
        _ enumeratedURL: URL,
        preservingRoot root: URL,
        displayRoot: URL,
        resolvedRoot: URL,
        isDirectory: Bool
    ) -> URL {
        let displayRootComponents = displayRoot.pathComponents
        let itemComponents = enumeratedURL.standardizedFileURL.pathComponents

        if itemComponents.starts(with: displayRootComponents) {
            let relativePath = itemComponents
                .dropFirst(displayRootComponents.count)
                .joined(separator: "/")

            return displayURL(root: root, relativePath: relativePath, isDirectory: isDirectory)
        }

        let resolvedRootComponents = resolvedRoot.pathComponents
        let resolvedItemComponents = enumeratedURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .pathComponents

        guard resolvedItemComponents.starts(with: resolvedRootComponents) else {
            return enumeratedURL
        }

        let relativePath = resolvedItemComponents
            .dropFirst(resolvedRootComponents.count)
            .joined(separator: "/")

        return displayURL(root: root, relativePath: relativePath, isDirectory: isDirectory)
    }

    private nonisolated static func displayURL(root: URL, relativePath: String, isDirectory: Bool) -> URL {
        guard !relativePath.isEmpty else {
            return root
        }

        return root.appendingPathComponent(relativePath, isDirectory: isDirectory)
    }

    private nonisolated static func makeFileItem(at url: URL) throws -> FileItem {
        try FileItem(url: url)
    }

    private nonisolated static func validateDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FileBrowserError.directoryNotFound(url)
        }

        guard isDirectory.boolValue else {
            throw FileBrowserError.notDirectory(url)
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw FileBrowserError.accessDenied(url)
        }
    }

    private nonisolated static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
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
