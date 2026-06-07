//
//  FileOperationServiceTests.swift
//  OpenPaneTests
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation
import Testing
@testable import OpenPane

struct FileOperationServiceTests {
    @Test func copiesFileToDestinationDirectory() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "source.txt", contents: "copy me")

        try await FileOperationService().copy(items: [sourceFile], to: temporaryDirectory.destinationURL)

        let copiedURL = temporaryDirectory.destinationURL.appendingPathComponent("source.txt")
        let copiedContents = try String(contentsOf: copiedURL, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: sourceFile.url.path))
        #expect(copiedContents == "copy me")
    }

    @Test func movesFileToDestinationDirectory() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "move.txt", contents: "move me")

        try await FileOperationService().move(items: [sourceFile], to: temporaryDirectory.destinationURL)

        let movedURL = temporaryDirectory.destinationURL.appendingPathComponent("move.txt")
        let movedContents = try String(contentsOf: movedURL, encoding: .utf8)
        #expect(!FileManager.default.fileExists(atPath: sourceFile.url.path))
        #expect(movedContents == "move me")
    }

    @Test func trashesItemsUsingTrashService() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "first.txt", contents: "first")
        let secondFile = try temporaryDirectory.createFile(named: "second.txt", contents: "second")
        let trashService = MockTrashService()

        try await FileOperationService(trashService: trashService).trash(items: [firstFile, secondFile])

        #expect(trashService.trashedURLs == [firstFile.url, secondFile.url])
    }

    @Test func trashThrowsUserReadableErrorWhenTrashServiceFails() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "trash.txt", contents: "trash me")
        let trashService = MockTrashService(error: NSError(
            domain: "OpenPaneTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Trash is unavailable"]
        ))

        await #expect(throws: FileOperationError.trashFailed(sourceFile.url, "Trash is unavailable")) {
            try await FileOperationService(trashService: trashService).trash(items: [sourceFile])
        }
    }

    @Test func renamesFile() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "old.txt", contents: "rename me")

        let renamedURL = try await FileOperationService().rename(item: sourceFile, to: "new.txt")

        #expect(renamedURL == temporaryDirectory.sourceURL.appendingPathComponent("new.txt"))
        let renamedContents = try String(contentsOf: renamedURL, encoding: .utf8)
        #expect(!FileManager.default.fileExists(atPath: sourceFile.url.path))
        #expect(renamedContents == "rename me")
    }

    @Test func createsFolder() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()

        let folderURL = try await FileOperationService().createFolder(named: "New Folder", in: temporaryDirectory.sourceURL)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func copyThrowsWhenDestinationExists() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "duplicate.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "duplicate.txt", contents: "existing")

        await #expect(throws: FileOperationError.destinationExists(temporaryDirectory.destinationURL.appendingPathComponent("duplicate.txt"))) {
            try await FileOperationService().copy(items: [sourceFile], to: temporaryDirectory.destinationURL)
        }
    }

    @Test func copyThrowsWhenSourceIsMissing() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let missingItem = try temporaryDirectory.createFile(named: "missing.txt", contents: "gone")
        try FileManager.default.removeItem(at: missingItem.url)

        await #expect(throws: FileOperationError.sourceDoesNotExist(missingItem.url)) {
            try await FileOperationService().copy(items: [missingItem], to: temporaryDirectory.destinationURL)
        }
    }

    @Test func emptyRenameTargetThrows() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "source.txt", contents: "source")

        await #expect(throws: FileOperationError.emptyName) {
            try await FileOperationService().rename(item: sourceFile, to: "   ")
        }
    }

    @Test func emptyFolderNameThrows() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()

        await #expect(throws: FileOperationError.emptyName) {
            try await FileOperationService().createFolder(named: "", in: temporaryDirectory.sourceURL)
        }
    }

    @Test func invalidFolderNameThrowsReadableError() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()

        await #expect(throws: FileOperationError.invalidName("Bad/Name")) {
            try await FileOperationService().createFolder(named: "Bad/Name", in: temporaryDirectory.sourceURL)
        }
    }
}

private final class MockTrashService: TrashServicing, @unchecked Sendable {
    private let error: Error?
    private let lock = NSLock()
    private var protectedTrashedURLs: [URL] = []

    init(error: Error? = nil) {
        self.error = error
    }

    var trashedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }

        return protectedTrashedURLs
    }

    func trashItem(at url: URL) throws {
        lock.lock()
        protectedTrashedURLs.append(url)
        lock.unlock()

        if let error {
            throw error
        }
    }
}

private struct OperationTestTemporaryDirectory {
    let rootURL: URL
    let sourceURL: URL
    let destinationURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneOperationTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceURL = rootURL.appendingPathComponent("Source", isDirectory: true)
        destinationURL = rootURL.appendingPathComponent("Destination", isDirectory: true)

        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    }

    func createFile(named name: String, contents: String) throws -> FileItem {
        try createFile(at: sourceURL.appendingPathComponent(name), contents: contents)
    }

    func createDestinationFile(named name: String, contents: String) throws -> FileItem {
        try createFile(at: destinationURL.appendingPathComponent(name), contents: contents)
    }

    private func createFile(at url: URL, contents: String) throws -> FileItem {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return try FileItem(url: url)
    }
}
