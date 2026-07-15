//
//  FileSearchServiceTests.swift
//  OpenPaneTests
//
//  Created by Christopher Rego on 6/7/26.
//

import Foundation
import Testing
@testable import OpenPane

struct FileSearchServiceTests {
    @Test func searchFindsNestedFilesAndFoldersByName() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        _ = try temporaryDirectory.createDirectory(named: "Nested")
        let nestedFile = try temporaryDirectory.createFile(named: "Nested/project-notes.txt", contents: "notes")
        let rootFile = try temporaryDirectory.createFile(named: "project-plan.txt", contents: "plan")
        _ = try temporaryDirectory.createFile(named: "unrelated.txt", contents: "nope")

        let results = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "project",
            includeHiddenFiles: false,
            limit: 500
        )

        #expect(Set(results.map { canonicalFileURL($0.url) }) == Set([nestedFile.url, rootFile.url].map(canonicalFileURL)))
    }

    @Test func searchExcludesHiddenFilesWhenRequested() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        _ = try temporaryDirectory.createFile(named: ".hidden-match.txt", contents: "hidden")
        let visibleFile = try temporaryDirectory.createFile(named: "visible-match.txt", contents: "visible")

        let results = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "match",
            includeHiddenFiles: false,
            limit: 500
        )

        #expect(results.map { canonicalFileURL($0.url) } == [canonicalFileURL(visibleFile.url)])
    }

    @Test func searchIncludesHiddenFilesWhenRequested() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        let hiddenFile = try temporaryDirectory.createFile(named: ".hidden-match.txt", contents: "hidden")
        let visibleFile = try temporaryDirectory.createFile(named: "visible-match.txt", contents: "visible")

        let results = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "match",
            includeHiddenFiles: true,
            limit: 500
        )

        #expect(Set(results.map { canonicalFileURL($0.url) }) == Set([hiddenFile.url, visibleFile.url].map(canonicalFileURL)))
    }

    @Test func searchRespectsLimit() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        _ = try temporaryDirectory.createFile(named: "match-one.txt", contents: "one")
        _ = try temporaryDirectory.createFile(named: "match-two.txt", contents: "two")
        _ = try temporaryDirectory.createFile(named: "match-three.txt", contents: "three")

        let results = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "match",
            includeHiddenFiles: false,
            limit: 2
        )

        #expect(results.count == 2)
    }

    @Test func searchBuildsExtendedMetadataOnlyForFilenameMatches() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        for index in 0..<50 {
            _ = try temporaryDirectory.createFile(
                named: "unrelated-\(index).txt",
                contents: "nope"
            )
        }
        _ = try temporaryDirectory.createFile(named: "needle-one.txt", contents: "one")
        _ = try temporaryDirectory.createFile(named: "needle-two.txt", contents: "two")
        let itemBuilder = CountingSearchItemBuilder()

        let results = try await FileSearchService(itemBuilder: itemBuilder.build).search(
            root: temporaryDirectory.url,
            query: "needle",
            includeHiddenFiles: false,
            limit: 500
        )

        #expect(results.count == 2)
        #expect(itemBuilder.buildCount == 2)
        #expect(results.allSatisfy { $0.hasExtendedMetadata })
    }

    @Test func contentsSearchFindsCaseInsensitiveNestedMatchWithLineAndExcerpt() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        let matchingFile = try temporaryDirectory.createFile(
            named: "Nested/notes.txt",
            contents: "first line\nA Needle appears here\nlast line"
        )
        _ = try temporaryDirectory.createFile(named: "Nested/other.txt", contents: "nothing here")

        let response = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "needle",
            kind: .contents,
            includeHiddenFiles: false,
            limit: 500
        )

        #expect(response.results.map { canonicalFileURL($0.item.url) } == [canonicalFileURL(matchingFile.url)])
        #expect(response.results.first?.contentMatch?.lineNumber == 2)
        #expect(response.results.first?.contentMatch?.excerpt == "A Needle appears here")
        #expect(response.skippedFileCount == 0)
    }

    @Test func contentsSearchFindsMatchesAcrossReadBoundaries() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        let boundaryOffset = 64 * 1_024 - 3
        let data = Data(repeating: UInt8(ascii: "a"), count: boundaryOffset) + Data("NeEdLe\n".utf8)
        let matchingFile = try temporaryDirectory.createDataFile(named: "boundary.txt", contents: data)

        let response = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "needle",
            kind: .contents,
            includeHiddenFiles: false,
            limit: 500
        )

        #expect(response.results.map { canonicalFileURL($0.item.url) } == [canonicalFileURL(matchingFile.url)])
        #expect(response.results.first?.contentMatch?.lineNumber == 1)
    }

    @Test func contentsSearchSkipsBinaryAndMalformedUTF8Files() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        _ = try temporaryDirectory.createDataFile(
            named: "binary.dat",
            contents: Data([0x6E, 0x65, 0x65, 0x64, 0x6C, 0x65, 0x00])
        )
        _ = try temporaryDirectory.createDataFile(
            named: "invalid.txt",
            contents: Data([0x6E, 0x65, 0x65, 0x64, 0x6C, 0x65, 0xFF])
        )
        let matchingFile = try temporaryDirectory.createFile(named: "valid.txt", contents: "needle")

        let response = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "needle",
            kind: .contents,
            includeHiddenFiles: false,
            limit: 500
        )

        #expect(response.results.map { canonicalFileURL($0.item.url) } == [canonicalFileURL(matchingFile.url)])
        #expect(response.skippedFileCount == 2)
    }

    @Test func contentsSearchDoesNotFollowSymlinksOrEnterPackages() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        let target = try temporaryDirectory.createFile(named: "target.txt", contents: "needle")
        let linkURL = temporaryDirectory.url.appendingPathComponent("linked.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: target.url)
        _ = try temporaryDirectory.createFile(named: "Example.app/inside.txt", contents: "needle")
        let regularFile = try temporaryDirectory.createFile(named: "outside.txt", contents: "needle")

        let response = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "needle",
            kind: .contents,
            includeHiddenFiles: false,
            limit: 500
        )

        #expect(
            Set(response.results.map { canonicalFileURL($0.item.url) }) ==
                Set([target.url, regularFile.url].map(canonicalFileURL))
        )
        #expect(response.results.map(\.item.name).contains("linked.txt") == false)
    }

    @Test func searchDoesNotWalkInsidePackageBundles() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        _ = try temporaryDirectory.createFile(named: "Outside-needle.txt", contents: "outside")
        _ = try temporaryDirectory.createFile(named: "Example.app/Inside-needle.txt", contents: "inside")

        let results = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "needle",
            includeHiddenFiles: false,
            limit: 500
        )

        #expect(results.map(\.name) == ["Outside-needle.txt"])
    }

    @Test func searchThroughSymlinkedRootReturnsDisplayRootURLs() async throws {
        let realDirectory = try SearchTestTemporaryDirectory()
        let linkedRoot = try SearchTestTemporaryDirectory.symlink(to: realDirectory.url)
        let nestedFile = try realDirectory.createFile(named: "Nested/project-notes.txt", contents: "notes")
        let expectedURL = linkedRoot.appendingPathComponent("Nested/project-notes.txt")

        let results = try await FileSearchService().search(
            root: linkedRoot,
            query: "project",
            includeHiddenFiles: false,
            limit: 500
        )

        #expect(results.map(\.url) == [expectedURL])
        #expect(results.first?.url != nestedFile.url)
    }

    @Test func searchSkipsUnreadableDescendantAndKeepsValidMatches() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        let visibleFile = try temporaryDirectory.createFile(named: "project-visible.txt", contents: "visible")
        let blockedDirectory = try temporaryDirectory.createDirectory(named: "Blocked")
        _ = try temporaryDirectory.createFile(named: "Blocked/project-blocked.txt", contents: "blocked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blockedDirectory.url.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blockedDirectory.url.path)
        }

        let results = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "project",
            includeHiddenFiles: false,
            limit: 500
        )

        #expect(results.map { canonicalFileURL($0.url) }.contains(canonicalFileURL(visibleFile.url)))
    }

    @Test func searchReturnsEmptyResultsForBlankQuery() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        _ = try temporaryDirectory.createFile(named: "project-plan.txt", contents: "plan")

        let results = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "   ",
            includeHiddenFiles: false,
            limit: 500
        )

        #expect(results.isEmpty)
    }

    @Test func searchReturnsEmptyResultsForNonPositiveLimit() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()
        _ = try temporaryDirectory.createFile(named: "project-plan.txt", contents: "plan")

        let zeroResults = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "project",
            includeHiddenFiles: false,
            limit: 0
        )
        let negativeResults = try await FileSearchService().search(
            root: temporaryDirectory.url,
            query: "project",
            includeHiddenFiles: false,
            limit: -1
        )

        #expect(zeroResults.isEmpty)
        #expect(negativeResults.isEmpty)
    }

    @Test func searchMissingRootThrowsFileBrowserError() async {
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneSearchServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        await #expect(throws: FileBrowserError.directoryNotFound(missingRoot)) {
            try await FileSearchService().search(
                root: missingRoot,
                query: "project",
                includeHiddenFiles: false,
                limit: 500
            )
        }
    }

    @Test func searchCancellationThrowsCancellationError() async throws {
        let temporaryDirectory = try SearchTestTemporaryDirectory()

        for index in 0..<1_000 {
            _ = try temporaryDirectory.createFile(named: "project-\(index).txt", contents: "\(index)")
        }

        let task = Task {
            try await FileSearchService().search(
                root: temporaryDirectory.url,
                query: "project",
                includeHiddenFiles: false,
                limit: 1_000
            )
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}

nonisolated private final class CountingSearchItemBuilder: @unchecked Sendable {
    private let lock = NSLock()
    private var protectedBuildCount = 0

    nonisolated var buildCount: Int {
        lock.withLock { protectedBuildCount }
    }

    nonisolated func build(_ url: URL) throws -> FileItem {
        lock.withLock { protectedBuildCount += 1 }
        return try FileItem(url: url)
    }
}

private func canonicalFileURL(_ url: URL) -> URL {
    url.resolvingSymlinksInPath().standardizedFileURL
}

private struct SearchTestTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneSearchServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createDirectory(named relativePath: String) throws -> FileItem {
        let directoryURL = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return try FileItem(url: directoryURL)
    }

    func createFile(named relativePath: String, contents: String) throws -> FileItem {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileItem(url: fileURL)
    }

    func createDataFile(named relativePath: String, contents: Data) throws -> FileItem {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL)
        return try FileItem(url: fileURL)
    }

    static func symlink(to destinationURL: URL) throws -> URL {
        let parentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneSearchServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let linkURL = parentURL.appendingPathComponent("LinkedRoot", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: destinationURL)
        return linkURL
    }
}
