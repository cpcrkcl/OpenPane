//
//  FileSearchService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import Foundation

nonisolated enum FileSearchKind: Sendable {
    case filename
    case contents
}

nonisolated struct FileContentMatch: Equatable, Hashable, Sendable {
    let lineNumber: Int
    let excerpt: String
}

nonisolated struct FileSearchResult: Identifiable, Equatable, Sendable {
    let item: FileItem
    let contentMatch: FileContentMatch?

    var id: FileItem.ID {
        item.id
    }
}

nonisolated struct FileSearchResponse: Equatable, Sendable {
    let results: [FileSearchResult]
    let skippedFileCount: Int

    static let empty = FileSearchResponse(results: [], skippedFileCount: 0)
}

nonisolated protocol FileSearchServicing: Sendable {
    nonisolated func search(
        root: URL,
        query: String,
        includeHiddenFiles: Bool,
        limit: Int
    ) async throws -> [FileItem]

    nonisolated func search(
        root: URL,
        query: String,
        kind: FileSearchKind,
        includeHiddenFiles: Bool,
        limit: Int
    ) async throws -> FileSearchResponse
}

extension FileSearchServicing {
    nonisolated func search(
        root: URL,
        query: String,
        kind: FileSearchKind,
        includeHiddenFiles: Bool,
        limit: Int
    ) async throws -> FileSearchResponse {
        guard kind == .filename else {
            return .empty
        }

        let items = try await search(
            root: root,
            query: query,
            includeHiddenFiles: includeHiddenFiles,
            limit: limit
        )
        return FileSearchResponse(
            results: items.map { FileSearchResult(item: $0, contentMatch: nil) },
            skippedFileCount: 0
        )
    }
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
        let response = try await search(
            root: root,
            query: query,
            kind: .filename,
            includeHiddenFiles: includeHiddenFiles,
            limit: limit
        )
        return response.results.map(\.item)
    }

    nonisolated func search(
        root: URL,
        query: String,
        kind: FileSearchKind,
        includeHiddenFiles: Bool,
        limit: Int = Self.defaultLimit
    ) async throws -> FileSearchResponse {
        let itemBuilder = itemBuilder
        return try await Self.runSearch {
            try Task.checkCancellation()
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedQuery.isEmpty, limit > 0 else {
                return .empty
            }

            do {
                try Self.validateDirectory(root)

                var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
                if !includeHiddenFiles {
                    options.insert(.skipsHiddenFiles)
                }
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

                var results: [FileSearchResult] = []
                var skippedFileCount = 0

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

                        switch kind {
                        case .filename:
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
                            results.append(
                                FileSearchResult(
                                    item: try itemBuilder(resultURL),
                                    contentMatch: nil
                                )
                            )

                        case .contents:
                            let resourceValues = try itemURL.resourceValues(
                                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                            )
                            guard resourceValues.isRegularFile == true,
                                  resourceValues.isSymbolicLink != true else {
                                continue
                            }

                            switch try Self.contentMatch(in: itemURL, query: trimmedQuery) {
                            case .match(let contentMatch):
                                let resultURL = Self.url(
                                    itemURL,
                                    preservingRoot: root,
                                    displayRoot: displayRoot,
                                    resolvedRoot: resolvedRoot,
                                    isDirectory: false
                                )
                                results.append(
                                    FileSearchResult(
                                        item: try itemBuilder(resultURL),
                                        contentMatch: contentMatch
                                    )
                                )
                            case .noMatch:
                                continue
                            case .skipped:
                                skippedFileCount += 1
                            }
                        }

                        if results.count >= limit {
                            break
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        if kind == .contents {
                            skippedFileCount += 1
                        }
                        continue
                    }
                }

                return FileSearchResponse(
                    results: results,
                    skippedFileCount: skippedFileCount
                )
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

    private nonisolated enum ContentMatchOutcome {
        case match(FileContentMatch)
        case noMatch
        case skipped
    }

    private nonisolated static func contentMatch(
        in url: URL,
        query: String
    ) throws -> ContentMatchOutcome {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let chunkSize = 64 * 1_024
        let retainedCharacterCount = max(query.count + 256, 1_024)
        var pendingBytes = Data()
        var carry = ""
        var carryStartLine = 1
        var isFirstChunk = true
        var firstMatch: FileContentMatch?

        while let chunk = try fileHandle.read(upToCount: chunkSize), !chunk.isEmpty {
            try Task.checkCancellation()

            if isFirstChunk {
                isFirstChunk = false
                guard !chunk.contains(0) else {
                    return .skipped
                }
            }

            pendingBytes.append(chunk)
            guard let decodedChunk = try decodeCompleteUTF8Prefix(from: &pendingBytes) else {
                return .skipped
            }

            let searchableText = carry + decodedChunk
            if firstMatch == nil, let range = searchableText.range(
                of: query,
                options: .caseInsensitive,
                locale: Locale(identifier: "en_US_POSIX")
            ) {
                let lineNumber = carryStartLine + searchableText[..<range.lowerBound]
                    .reduce(into: 0) { count, character in
                        if isLineBreak(character) {
                            count += 1
                        }
                    }
                firstMatch = FileContentMatch(
                    lineNumber: lineNumber,
                    excerpt: excerpt(in: searchableText, around: range)
                )
            }

            guard searchableText.count > retainedCharacterCount else {
                carry = searchableText
                continue
            }

            let carryStartIndex = searchableText.index(
                searchableText.endIndex,
                offsetBy: -retainedCharacterCount
            )
            carryStartLine += searchableText[..<carryStartIndex]
                .reduce(into: 0) { count, character in
                    if isLineBreak(character) {
                        count += 1
                    }
                }
            carry = String(searchableText[carryStartIndex...])
        }

        guard pendingBytes.isEmpty else {
            return .skipped
        }

        return firstMatch.map(ContentMatchOutcome.match) ?? .noMatch
    }

    private nonisolated static func decodeCompleteUTF8Prefix(from data: inout Data) throws -> String? {
        let maximumTrailingByteCount = min(3, data.count)
        for trailingByteCount in 0...maximumTrailingByteCount {
            let prefixLength = data.count - trailingByteCount
            let prefix = data.prefix(prefixLength)
            guard let decoded = String(data: prefix, encoding: .utf8) else {
                continue
            }

            data = Data(data.suffix(trailingByteCount))
            return decoded
        }

        return nil
    }

    private nonisolated static func excerpt(
        in text: String,
        around range: Range<String.Index>,
        maximumCharacterCount: Int = 180
    ) -> String {
        let lineStart = text[..<range.lowerBound].lastIndex(where: isLineBreak)
            .map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[range.upperBound...].firstIndex(where: isLineBreak) ?? text.endIndex
        let line = text[lineStart..<lineEnd]
        let leadingCharacterCount = max(0, maximumCharacterCount / 2)
        let excerptStart = line.index(
            range.lowerBound,
            offsetBy: -leadingCharacterCount,
            limitedBy: line.startIndex
        ) ?? line.startIndex
        let excerptEnd = line.index(
            range.upperBound,
            offsetBy: leadingCharacterCount,
            limitedBy: line.endIndex
        ) ?? line.endIndex
        let isTruncatedAtStart = excerptStart > line.startIndex
        let isTruncatedAtEnd = excerptEnd < line.endIndex
        let normalized = line[excerptStart..<excerptEnd]
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (isTruncatedAtStart ? "…" : "") +
            normalized +
            (isTruncatedAtEnd ? "…" : "")
    }

    /// Swift treats CRLF as one extended grapheme cluster, so checking only
    /// for `"\n"` misses every Windows-style line ending. Keep line counting
    /// and excerpt boundaries aligned for the common Unicode line separators.
    private nonisolated static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" ||
            character == "\r" ||
            character == "\r\n" ||
            character == "\u{0085}" ||
            character == "\u{2028}" ||
            character == "\u{2029}"
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
