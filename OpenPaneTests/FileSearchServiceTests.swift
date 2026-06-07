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

        #expect(Set(results.map(\.url)) == Set([nestedFile.url, rootFile.url]))
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

        #expect(results.map(\.url) == [visibleFile.url])
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

        #expect(Set(results.map(\.url)) == Set([hiddenFile.url, visibleFile.url]))
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
}
