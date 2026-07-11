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

        #expect(Set(items.map(\.name)) == Set(["notes.txt", "photo.jpg"]))
        #expect(items.allSatisfy { !$0.hasExtendedMetadata })
    }

    @Test func returnsDirectoriesAndFilesWithoutOwningDisplayOrder() async throws {
        let temporaryDirectory = try ServiceTestTemporaryDirectory()
        try temporaryDirectory.createFile(named: "Alpha.txt")
        try temporaryDirectory.createDirectory(named: "Zoo")

        let items = try await FileBrowserService()
            .contentsOfDirectory(at: temporaryDirectory.url, includeHiddenFiles: false)

        #expect(Set(items.map(\.name)) == Set(["Zoo", "Alpha.txt"]))
        #expect(items.first(where: { $0.name == "Zoo" })?.isDirectory == true)
    }

    @Test func returnsEveryEntryForViewModelSorting() async throws {
        let temporaryDirectory = try ServiceTestTemporaryDirectory()
        try temporaryDirectory.createFile(named: "Charlie.txt")
        try temporaryDirectory.createFile(named: "Alpha.txt")
        try temporaryDirectory.createFile(named: "Bravo.txt")

        let items = try await FileBrowserService()
            .contentsOfDirectory(at: temporaryDirectory.url, includeHiddenFiles: false)

        #expect(Set(items.map(\.name)) == Set(["Alpha.txt", "Bravo.txt", "Charlie.txt"]))
    }

    @Test func directorySnapshotFingerprintChangesWhenEntriesChange() async throws {
        let temporaryDirectory = try ServiceTestTemporaryDirectory()
        try temporaryDirectory.createFile(named: "stable.txt")
        let service = FileBrowserService()

        let initialSnapshot = try await service.directorySnapshot(
            at: temporaryDirectory.url,
            includeHiddenFiles: false,
            includeFingerprint: true,
            priority: .utility
        )
        let unchangedSnapshot = try await service.directorySnapshot(
            at: temporaryDirectory.url,
            includeHiddenFiles: false,
            includeFingerprint: true,
            priority: .utility
        )
        try temporaryDirectory.createFile(named: "added.txt")
        let changedSnapshot = try await service.directorySnapshot(
            at: temporaryDirectory.url,
            includeHiddenFiles: false,
            includeFingerprint: true,
            priority: .utility
        )

        #expect(initialSnapshot.fingerprint == unchangedSnapshot.fingerprint)
        #expect(initialSnapshot.fingerprint != changedSnapshot.fingerprint)
        #expect(Set(changedSnapshot.items.map(\.name)) == Set(["stable.txt", "added.txt"]))
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
