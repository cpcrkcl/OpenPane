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

    @Test func duplicatesSimpleFile() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "README", contents: "copy me")

        try await FileOperationService().duplicate(items: [sourceFile])

        let duplicateURL = temporaryDirectory.sourceURL.appendingPathComponent("README copy")
        let duplicateContents = try String(contentsOf: duplicateURL, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: sourceFile.url.path))
        #expect(duplicateContents == "copy me")
    }

    @Test func duplicatesFileWithExtensionAndPreservesExtension() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "File.txt", contents: "copy me")

        try await FileOperationService().duplicate(items: [sourceFile])

        let duplicateURL = temporaryDirectory.sourceURL.appendingPathComponent("File copy.txt")
        let duplicateContents = try String(contentsOf: duplicateURL, encoding: .utf8)
        #expect(duplicateContents == "copy me")
    }

    @Test func duplicateIncrementsNameWhenCopyAlreadyExists() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "File.txt", contents: "source")
        _ = try temporaryDirectory.createFile(named: "File copy.txt", contents: "existing")

        try await FileOperationService().duplicate(items: [sourceFile])

        let duplicateURL = temporaryDirectory.sourceURL.appendingPathComponent("File copy 2.txt")
        let duplicateContents = try String(contentsOf: duplicateURL, encoding: .utf8)
        #expect(duplicateContents == "source")
    }

    @Test func duplicatesFolder() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let folderURL = temporaryDirectory.sourceURL.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        try "nested".write(
            to: folderURL.appendingPathComponent("note.txt"),
            atomically: true,
            encoding: .utf8
        )
        let folderItem = try FileItem(url: folderURL)

        try await FileOperationService().duplicate(items: [folderItem])

        let duplicateURL = temporaryDirectory.sourceURL.appendingPathComponent("Folder copy", isDirectory: true)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: duplicateURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        let nestedContents = try String(contentsOf: duplicateURL.appendingPathComponent("note.txt"), encoding: .utf8)
        #expect(nestedContents == "nested")
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

    @Test func batchRenamePreviewNamesUseBaseNameAndStartingNumber() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "a.jpg", contents: "a")
        let secondFile = try temporaryDirectory.createFile(named: "b.jpg", contents: "b")

        let names = try FileOperationService.batchRenamePreviewNames(
            for: [secondFile, firstFile],
            baseName: "Photo",
            startingNumber: 7
        )

        #expect(names == ["Photo 7.jpg", "Photo 8.jpg"])
    }

    @Test func batchRenamePreservesExtensions() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "IMG_1.jpg", contents: "one")
        let secondFile = try temporaryDirectory.createFile(named: "IMG_2.png", contents: "two")

        let renamedURLs = try await FileOperationService().batchRename(
            items: [firstFile, secondFile],
            baseName: "Photo",
            startingNumber: 1,
            preserveExtensions: true
        )

        #expect(Set(renamedURLs.map(\.lastPathComponent)) == Set(["Photo 1.jpg", "Photo 2.png"]))
        #expect(FileManager.default.fileExists(atPath: temporaryDirectory.sourceURL.appendingPathComponent("Photo 1.jpg").path))
        #expect(FileManager.default.fileExists(atPath: temporaryDirectory.sourceURL.appendingPathComponent("Photo 2.png").path))
    }

    @Test func batchRenameCanDropExtensions() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "IMG_1.jpg", contents: "one")
        let secondFile = try temporaryDirectory.createFile(named: "IMG_2.png", contents: "two")

        let renamedURLs = try await FileOperationService().batchRename(
            items: [firstFile, secondFile],
            baseName: "Photo",
            startingNumber: 1,
            preserveExtensions: false
        )

        #expect(Set(renamedURLs.map(\.lastPathComponent)) == Set(["Photo 1", "Photo 2"]))
    }

    @Test func batchRenameDetectsExistingDestinationBeforeRenaming() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "IMG_1.jpg", contents: "one")
        let secondFile = try temporaryDirectory.createFile(named: "IMG_2.jpg", contents: "two")
        _ = try temporaryDirectory.createFile(named: "Photo 1.jpg", contents: "existing")

        await #expect(throws: FileOperationError.destinationExists(temporaryDirectory.sourceURL.appendingPathComponent("Photo 1.jpg"))) {
            try await FileOperationService().batchRename(
                items: [firstFile, secondFile],
                baseName: "Photo",
                startingNumber: 1,
                preserveExtensions: true
            )
        }

        #expect(FileManager.default.fileExists(atPath: firstFile.url.path))
        #expect(FileManager.default.fileExists(atPath: secondFile.url.path))
    }

    @Test func createsFolder() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()

        let folderURL = try await FileOperationService().createFolder(named: "New Folder", in: temporaryDirectory.sourceURL)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func createsEmptyFile() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()

        let fileURL = try await FileOperationService().createFile(named: "Untitled.txt", in: temporaryDirectory.sourceURL)

        var isDirectory: ObjCBool = true
        #expect(FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory))
        #expect(!isDirectory.boolValue)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect(attributes[.size] as? Int == 0)
    }

    @Test func emptyFileNameThrows() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()

        await #expect(throws: FileOperationError.emptyName) {
            try await FileOperationService().createFile(named: "   ", in: temporaryDirectory.sourceURL)
        }
    }

    @Test func createFileCollisionThrowsReadableError() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        _ = try temporaryDirectory.createFile(named: "Untitled.txt", contents: "existing")

        await #expect(throws: FileOperationError.destinationExists(temporaryDirectory.sourceURL.appendingPathComponent("Untitled.txt"))) {
            try await FileOperationService().createFile(named: "Untitled.txt", in: temporaryDirectory.sourceURL)
        }
    }

    @Test func createFileNameWithSlashThrowsReadableError() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()

        await #expect(throws: FileOperationError.invalidName("Bad/Name.txt")) {
            try await FileOperationService().createFile(named: "Bad/Name.txt", in: temporaryDirectory.sourceURL)
        }
    }

    @Test func copyCancelsWhenDestinationExistsByDefault() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "duplicate.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "duplicate.txt", contents: "existing")

        await #expect(throws: FileOperationError.operationCancelled(temporaryDirectory.destinationURL.appendingPathComponent("duplicate.txt"))) {
            try await FileOperationService().copy(items: [sourceFile], to: temporaryDirectory.destinationURL)
        }
    }

    @Test func copyKeepBothPreservesExtensionAndCreatesCopyName() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "file.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "file.txt", contents: "existing")

        try await FileOperationService().copy(
            items: [sourceFile],
            to: temporaryDirectory.destinationURL,
            conflictResolution: .keepBoth
        )

        let existingContents = try String(
            contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("file.txt"),
            encoding: .utf8
        )
        let copiedContents = try String(
            contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("file copy.txt"),
            encoding: .utf8
        )
        #expect(existingContents == "existing")
        #expect(copiedContents == "source")
    }

    @Test func copyKeepBothIncrementsCopyNameWhenCopyAlreadyExists() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "file.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "file.txt", contents: "existing")
        _ = try temporaryDirectory.createDestinationFile(named: "file copy.txt", contents: "copy")

        try await FileOperationService().copy(
            items: [sourceFile],
            to: temporaryDirectory.destinationURL,
            conflictResolution: .keepBoth
        )

        let copiedContents = try String(
            contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("file copy 2.txt"),
            encoding: .utf8
        )
        #expect(copiedContents == "source")
    }

    @Test func copySkipLeavesExistingDestinationAndContinues() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let duplicateFile = try temporaryDirectory.createFile(named: "duplicate.txt", contents: "source")
        let otherFile = try temporaryDirectory.createFile(named: "other.txt", contents: "other")
        _ = try temporaryDirectory.createDestinationFile(named: "duplicate.txt", contents: "existing")

        try await FileOperationService().copy(
            items: [duplicateFile, otherFile],
            to: temporaryDirectory.destinationURL,
            conflictResolution: .skip
        )

        let duplicateContents = try String(
            contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("duplicate.txt"),
            encoding: .utf8
        )
        let otherContents = try String(
            contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("other.txt"),
            encoding: .utf8
        )
        #expect(duplicateContents == "existing")
        #expect(otherContents == "other")
    }

    @Test func copyReplaceTrashesExistingDestinationAndCopiesSource() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "replace.txt", contents: "source")
        let existingFile = try temporaryDirectory.createDestinationFile(named: "replace.txt", contents: "existing")
        let trashService = RemovingTrashService()

        try await FileOperationService(trashService: trashService).copy(
            items: [sourceFile],
            to: temporaryDirectory.destinationURL,
            conflictResolution: .replace
        )

        let replacedContents = try String(
            contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("replace.txt"),
            encoding: .utf8
        )
        #expect(replacedContents == "source")
        #expect(trashService.trashedURLs == [existingFile.url])
    }

    @Test func copyPreflightsAllDestinationsBeforeCopying() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "first.txt", contents: "first")
        let duplicateFile = try temporaryDirectory.createFile(named: "duplicate.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "duplicate.txt", contents: "existing")

        await #expect(throws: FileOperationError.operationCancelled(temporaryDirectory.destinationURL.appendingPathComponent("duplicate.txt"))) {
            try await FileOperationService().copy(items: [firstFile, duplicateFile], to: temporaryDirectory.destinationURL)
        }

        #expect(!FileManager.default.fileExists(atPath: temporaryDirectory.destinationURL.appendingPathComponent("first.txt").path))
    }

    @Test func movePreflightsAllDestinationsBeforeMoving() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "first.txt", contents: "first")
        let duplicateFile = try temporaryDirectory.createFile(named: "duplicate.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "duplicate.txt", contents: "existing")

        await #expect(throws: FileOperationError.operationCancelled(temporaryDirectory.destinationURL.appendingPathComponent("duplicate.txt"))) {
            try await FileOperationService().move(items: [firstFile, duplicateFile], to: temporaryDirectory.destinationURL)
        }

        #expect(FileManager.default.fileExists(atPath: firstFile.url.path))
        #expect(!FileManager.default.fileExists(atPath: temporaryDirectory.destinationURL.appendingPathComponent("first.txt").path))
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

    @Test func dotFolderNamesThrowReadableError() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()

        await #expect(throws: FileOperationError.invalidName("..")) {
            try await FileOperationService().createFolder(named: "..", in: temporaryDirectory.sourceURL)
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

private final class RemovingTrashService: TrashServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var protectedTrashedURLs: [URL] = []

    var trashedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }

        return protectedTrashedURLs
    }

    func trashItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)

        lock.lock()
        protectedTrashedURLs.append(url)
        lock.unlock()
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
