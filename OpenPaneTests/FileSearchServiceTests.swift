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
