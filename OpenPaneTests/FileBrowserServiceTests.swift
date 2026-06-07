//
//  FileBrowserServiceTests.swift
//  OpenPaneTests
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation
import Testing
@testable import OpenPane

struct FileBrowserServiceTests {
    @Test func listsFilesInDirectory() async throws {
        let temporaryDirectory = try ServiceTestTemporaryDirectory()
        try temporaryDirectory.createFile(named: "notes.txt")
        try temporaryDirectory.createFile(named: "photo.jpg")

        let items = try await FileBrowserService()
            .contentsOfDirectory(at: temporaryDirectory.url, includeHiddenFiles: false)

        #expect(items.map(\.name) == ["notes.txt", "photo.jpg"])
    }

    @Test func sortsDirectoriesBeforeFiles() async throws {
        let temporaryDirectory = try ServiceTestTemporaryDirectory()
        try temporaryDirectory.createFile(named: "Alpha.txt")
        try temporaryDirectory.createDirectory(named: "Zoo")

        let items = try await FileBrowserService()
            .contentsOfDirectory(at: temporaryDirectory.url, includeHiddenFiles: false)

        #expect(items.map(\.name) == ["Zoo", "Alpha.txt"])
        #expect(items.first?.isDirectory == true)
    }

    @Test func sortsNamesAlphabetically() async throws {
        let temporaryDirectory = try ServiceTestTemporaryDirectory()
        try temporaryDirectory.createFile(named: "Charlie.txt")
        try temporaryDirectory.createFile(named: "Alpha.txt")
        try temporaryDirectory.createFile(named: "Bravo.txt")

        let items = try await FileBrowserService()
            .contentsOfDirectory(at: temporaryDirectory.url, includeHiddenFiles: false)

        #expect(items.map(\.name) == ["Alpha.txt", "Bravo.txt", "Charlie.txt"])
    }

    @Test func excludesHiddenFilesByDefault() async throws {
        let temporaryDirectory = try ServiceTestTemporaryDirectory()
        try temporaryDirectory.createFile(named: "visible.txt")
        try temporaryDirectory.createFile(named: ".hidden")

        let items = try await FileBrowserService()
            .contentsOfDirectory(at: temporaryDirectory.url, includeHiddenFiles: false)

        #expect(items.map(\.name) == ["visible.txt"])
    }

    @Test func includesHiddenFilesWhenRequested() async throws {
        let temporaryDirectory = try ServiceTestTemporaryDirectory()
        try temporaryDirectory.createFile(named: "visible.txt")
        try temporaryDirectory.createFile(named: ".hidden")

        let items = try await FileBrowserService()
            .contentsOfDirectory(at: temporaryDirectory.url, includeHiddenFiles: true)

        #expect(Set(items.map(\.name)) == Set([".hidden", "visible.txt"]))
    }

    @Test func missingDirectoryThrowsReadableError() async throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneMissingDirectoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        await #expect(throws: FileBrowserError.directoryNotFound(missingURL)) {
            try await FileBrowserService().contentsOfDirectory(at: missingURL, includeHiddenFiles: false)
        }
    }

    @Test func fileURLThrowsNotDirectoryError() async throws {
        let temporaryDirectory = try ServiceTestTemporaryDirectory()
        try temporaryDirectory.createFile(named: "notes.txt")
        let fileURL = temporaryDirectory.url.appendingPathComponent("notes.txt")

        await #expect(throws: FileBrowserError.notDirectory(fileURL)) {
            try await FileBrowserService().contentsOfDirectory(at: fileURL, includeHiddenFiles: false)
        }
    }
}

private struct ServiceTestTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createDirectory(named name: String) throws {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(name, isDirectory: true),
            withIntermediateDirectories: false
        )
    }

    func createFile(named name: String) throws {
        let fileURL = url.appendingPathComponent(name)
        let didCreateFile = FileManager.default.createFile(atPath: fileURL.path, contents: Data(name.utf8))

        #expect(didCreateFile)
    }
}
