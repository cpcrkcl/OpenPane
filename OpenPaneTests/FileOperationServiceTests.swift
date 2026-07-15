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

    @Test func copyReportsByteAndItemProgress() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "first.txt", contents: "one")
        let secondFile = try temporaryDirectory.createFile(named: "second.txt", contents: "two")
        let progressRecorder = ProgressRecorder()

        try await FileOperationService().copy(
            items: [firstFile, secondFile],
            to: temporaryDirectory.destinationURL,
            conflictResolution: .cancel,
            progressHandler: { progress in
                progressRecorder.append(progress)
            }
        )

        #expect(progressRecorder.progresses.first?.totalByteCount == 6)
        #expect(progressRecorder.progresses.contains {
            $0.currentItemName == "first.txt" && $0.completedByteCount == 3
        })
        #expect(progressRecorder.progresses.last == FileOperationProgress(
            completedItemCount: 2,
            totalItemCount: 2,
            currentItemName: "second.txt",
            completedByteCount: 6,
            totalByteCount: 6
        ))
    }

    @Test func crossVolumeMoveUsesByteTransferAndPublishesBeforeRemovingSource() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "move.txt", contents: "abcdef")
        let progressRecorder = ProgressRecorder()
        let transferService = SimulatedTransferService(intermediateByteCount: 2)

        try await FileOperationService(
            fileTransferService: transferService,
            volumeIdentityProvider: FixedVolumeIdentityProvider(isSameVolume: false)
        ).move(
            items: [sourceFile],
            to: temporaryDirectory.destinationURL,
            conflictResolution: .cancel,
            progressHandler: progressRecorder.append
        )

        let destinationURL = temporaryDirectory.destinationURL.appendingPathComponent("move.txt")
        #expect(FileManager.default.fileExists(atPath: destinationURL.path))
        #expect(FileManager.default.fileExists(atPath: sourceFile.url.path) == false)
        #expect(progressRecorder.progresses.contains { $0.completedByteCount == 2 && $0.totalByteCount == 6 })
        #expect(progressRecorder.progresses.last?.completedByteCount == 6)
    }

    @Test func sameVolumeMoveKeepsItemProgressAndSkipsByteTransfer() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "move.txt", contents: "abcdef")
        let progressRecorder = ProgressRecorder()
        let transferService = SimulatedTransferService(intermediateByteCount: 2)

        try await FileOperationService(
            fileTransferService: transferService,
            volumeIdentityProvider: FixedVolumeIdentityProvider(isSameVolume: true)
        ).move(
            items: [sourceFile],
            to: temporaryDirectory.destinationURL,
            conflictResolution: .cancel,
            progressHandler: progressRecorder.append
        )

        #expect(transferService.copyCount == 0)
        #expect(progressRecorder.progresses.allSatisfy { $0.completedByteCount == nil && $0.totalByteCount == nil })
    }

    @Test func cancellationRemovesOnlyCurrentStagingDestination() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "first.txt", contents: "first")
        let secondFile = try temporaryDirectory.createFile(named: "second.txt", contents: "second")
        let transferService = CancellingTransferService(cancelOnCopyNumber: 2)

        await #expect(throws: CancellationError.self) {
            try await FileOperationService(fileTransferService: transferService).copy(
                items: [firstFile, secondFile],
                to: temporaryDirectory.destinationURL,
                conflictResolution: .cancel,
                progressHandler: nil
            )
        }

        #expect(FileManager.default.fileExists(atPath: temporaryDirectory.destinationURL.appendingPathComponent("first.txt").path))
        #expect(FileManager.default.fileExists(atPath: temporaryDirectory.destinationURL.appendingPathComponent("second.txt").path) == false)
        #expect(FileManager.default.fileExists(atPath: secondFile.url.path))
        #expect(try temporaryDirectory.transferStagingURLs().isEmpty)
    }

    @Test func emptyItemOperationsFailInsteadOfReportingFalseSuccess() async {
        let service = FileOperationService()
        let destinationURL = FileManager.default.temporaryDirectory

        await #expect(throws: FileOperationError.noItems) {
            try await service.copy(items: [], to: destinationURL)
        }
        await #expect(throws: FileOperationError.noItems) {
            try await service.move(items: [], to: destinationURL)
        }
        await #expect(throws: FileOperationError.noItems) {
            try await service.trash(items: [])
        }
        await #expect(throws: FileOperationError.noItems) {
            try await service.duplicate(items: [])
        }
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

    @Test func archiveURLUsesSingleItemName() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "File.txt", contents: "zip me")

        let archiveURL = try FileOperationService.archiveURL(for: [sourceFile])

        #expect(archiveURL == temporaryDirectory.sourceURL.appendingPathComponent("File.txt.zip"))
    }

    @Test func archiveURLUsesArchiveNameForMultipleItems() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "First.txt", contents: "one")
        let secondFile = try temporaryDirectory.createFile(named: "Second.txt", contents: "two")

        let archiveURL = try FileOperationService.archiveURL(for: [firstFile, secondFile])

        #expect(archiveURL == temporaryDirectory.sourceURL.appendingPathComponent("Archive.zip"))
    }

    @Test func archiveURLIncrementsWhenArchiveAlreadyExists() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "First.txt", contents: "one")
        let secondFile = try temporaryDirectory.createFile(named: "Second.txt", contents: "two")
        _ = try temporaryDirectory.createFile(named: "Archive.zip", contents: "existing")
        _ = try temporaryDirectory.createFile(named: "Archive 2.zip", contents: "existing")

        let archiveURL = try FileOperationService.archiveURL(for: [firstFile, secondFile])

        #expect(archiveURL == temporaryDirectory.sourceURL.appendingPathComponent("Archive 3.zip"))
    }

    @Test func archiveURLUsesFolderName() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let folderURL = temporaryDirectory.sourceURL.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        let folderItem = try FileItem(url: folderURL)

        let archiveURL = try FileOperationService.archiveURL(for: [folderItem])

        #expect(archiveURL == temporaryDirectory.sourceURL.appendingPathComponent("Folder.zip"))
    }

    @Test func compressReportsSourceAndPublishedArchiveNames() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "File.txt", contents: "zip me")
        let progressRecorder = ProgressRecorder()

        let archiveURL = try await FileOperationService(
            archiveProcessRunner: SuccessfulArchiveProcessRunner(archiveContents: "archive")
        ).compress(items: [sourceFile], progressHandler: { progress in
            progressRecorder.append(progress)
        })

        #expect(progressRecorder.progresses == [
            FileOperationProgress(completedItemCount: 0, totalItemCount: 1),
            FileOperationProgress(completedItemCount: 0, totalItemCount: 1, currentItemName: "File.txt"),
            FileOperationProgress(
                completedItemCount: 1,
                totalItemCount: 1,
                currentItemName: archiveURL.lastPathComponent
            )
        ])
    }

    @Test func compressMultipleItemsWithSystemDittoIncludesEverySelectedEntry() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "First.txt", contents: "one")
        let secondFile = try temporaryDirectory.createFile(named: "Second.txt", contents: "two")
        let linkURL = temporaryDirectory.sourceURL.appendingPathComponent("First Link.txt")
        try FileManager.default.createSymbolicLink(
            atPath: linkURL.path,
            withDestinationPath: firstFile.url.lastPathComponent
        )
        let linkedFile = try FileItem(url: linkURL)

        let archiveURL = try await FileOperationService().compress(items: [firstFile, secondFile, linkedFile])
        let entryNames = try zipEntryNames(at: archiveURL)
        let extractedURL = temporaryDirectory.rootURL.appendingPathComponent("Extracted", isDirectory: true)
        try extractZip(at: archiveURL, to: extractedURL)
        let extractedLinkDestination = try FileManager.default.destinationOfSymbolicLink(
            atPath: extractedURL.appendingPathComponent("First Link.txt").path
        )

        #expect(archiveURL == temporaryDirectory.sourceURL.appendingPathComponent("Archive.zip"))
        #expect(FileManager.default.fileExists(atPath: archiveURL.path))
        #expect(entryNames.contains("First.txt"))
        #expect(entryNames.contains("Second.txt"))
        #expect(entryNames.contains("First Link.txt"))
        #expect(!entryNames.contains { $0.hasPrefix("OpenPane-Archive-") })
        #expect(extractedLinkDestination == "First.txt")
        #expect(!(try hasTemporaryArchiveArtifacts(in: temporaryDirectory.sourceURL)))
    }

    @Test func compressFailureRemovesOnlyOwnedPartialArchive() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "File.txt", contents: "zip me")
        let archiveURL = temporaryDirectory.sourceURL.appendingPathComponent("File.txt.zip")
        let archiveProcessRunner = FailingArchiveProcessRunner(
            error: FileOperationError.operationFailed("compress", archiveURL, "Simulated archive failure"),
            partialArchiveContents: "partial",
            competingArchiveURL: archiveURL,
            competingArchiveContents: "created by another process"
        )

        await #expect(throws: FileOperationError.operationFailed("compress", archiveURL, "Simulated archive failure")) {
            _ = try await FileOperationService(archiveProcessRunner: archiveProcessRunner)
                .compress(items: [sourceFile])
        }

        #expect(FileManager.default.fileExists(atPath: archiveURL.path))
        #expect(try String(contentsOf: archiveURL, encoding: .utf8) == "created by another process")
        #expect(FileManager.default.fileExists(atPath: sourceFile.url.path))
        #expect(!(try hasTemporaryArchiveArtifacts(in: temporaryDirectory.sourceURL)))
    }

    @Test func compressCancellationRemovesOnlyOwnedPartialArchive() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "File.txt", contents: "zip me")
        let archiveURL = temporaryDirectory.sourceURL.appendingPathComponent("File.txt.zip")
        let archiveProcessRunner = FailingArchiveProcessRunner(
            error: CancellationError(),
            partialArchiveContents: "partial",
            competingArchiveURL: archiveURL,
            competingArchiveContents: "created by another process"
        )

        await #expect(throws: CancellationError.self) {
            _ = try await FileOperationService(archiveProcessRunner: archiveProcessRunner)
                .compress(items: [sourceFile])
        }

        #expect(FileManager.default.fileExists(atPath: archiveURL.path))
        #expect(try String(contentsOf: archiveURL, encoding: .utf8) == "created by another process")
        #expect(FileManager.default.fileExists(atPath: sourceFile.url.path))
        #expect(!(try hasTemporaryArchiveArtifacts(in: temporaryDirectory.sourceURL)))
    }

    @Test func compressPublishesToNextSuffixWhenArchiveNameIsClaimedDuringCompression() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "File.txt", contents: "zip me")
        let competingArchiveURL = temporaryDirectory.sourceURL.appendingPathComponent("File.txt.zip")
        let archiveProcessRunner = LateCollisionArchiveProcessRunner(
            competingArchiveURL: competingArchiveURL,
            competingArchiveContents: "created by another process",
            archiveContents: "OpenPane archive"
        )

        let archiveURL = try await FileOperationService(archiveProcessRunner: archiveProcessRunner)
            .compress(items: [sourceFile])

        let expectedArchiveURL = temporaryDirectory.sourceURL.appendingPathComponent("File.txt 2.zip")
        #expect(archiveURL == expectedArchiveURL)
        #expect(try String(contentsOf: competingArchiveURL, encoding: .utf8) == "created by another process")
        #expect(try String(contentsOf: archiveURL, encoding: .utf8) == "OpenPane archive")
        #expect(!(try hasTemporaryArchiveArtifacts(in: temporaryDirectory.sourceURL)))
    }

    @Test func compressFailsWithoutNonAtomicPublicationFallback() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "File.txt", contents: "zip me")
        let archiveURL = temporaryDirectory.sourceURL.appendingPathComponent("File.txt.zip")
        let fileSystem = FailingFileSystem(exclusiveMoveError: POSIXError(.EINVAL))

        await #expect(throws: FileOperationError.self) {
            _ = try await FileOperationService(
                fileSystem: fileSystem,
                archiveProcessRunner: SuccessfulArchiveProcessRunner(archiveContents: "OpenPane archive")
            ).compress(items: [sourceFile])
        }

        #expect(!FileManager.default.fileExists(atPath: archiveURL.path))
        #expect(!(try hasTemporaryArchiveArtifacts(in: temporaryDirectory.sourceURL)))
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

    @Test func renameToSameNameIsNoOp() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "same.txt", contents: "same")

        let renamedURL = try await FileOperationService().rename(item: sourceFile, to: "same.txt")

        #expect(renamedURL == sourceFile.url)
        #expect(FileManager.default.fileExists(atPath: sourceFile.url.path))
        let contents = try String(contentsOf: sourceFile.url, encoding: .utf8)
        #expect(contents == "same")
    }

    @Test func caseOnlyRenamePreservesContents() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "note.txt", contents: "rename case")

        let renamedURL = try await FileOperationService().rename(item: sourceFile, to: "Note.txt")

        #expect(renamedURL == temporaryDirectory.sourceURL.appendingPathComponent("Note.txt"))
        let renamedContents = try String(contentsOf: renamedURL, encoding: .utf8)
        let directoryNames = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.sourceURL.path)
        #expect(renamedContents == "rename case")
        #expect(directoryNames.contains("Note.txt"))
    }

    @Test func renameToDifferentExistingItemThrowsAndLeavesFilesUntouched() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "old.txt", contents: "source")
        let existingFile = try temporaryDirectory.createFile(named: "existing.txt", contents: "existing")

        await #expect(throws: FileOperationError.destinationExists(existingFile.url)) {
            try await FileOperationService().rename(item: sourceFile, to: "existing.txt")
        }

        let sourceContents = try String(contentsOf: sourceFile.url, encoding: .utf8)
        let existingContents = try String(contentsOf: existingFile.url, encoding: .utf8)
        #expect(sourceContents == "source")
        #expect(existingContents == "existing")
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

    @Test func batchRenameHandlesRenameChainThroughTemporaryNames() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "Photo 1.jpg", contents: "one")
        let secondFile = try temporaryDirectory.createFile(named: "Photo 2.jpg", contents: "two")

        let renamedURLs = try await FileOperationService().batchRename(
            items: [firstFile, secondFile],
            baseName: "Photo",
            startingNumber: 2,
            preserveExtensions: true
        )

        let photo2URL = temporaryDirectory.sourceURL.appendingPathComponent("Photo 2.jpg")
        let photo3URL = temporaryDirectory.sourceURL.appendingPathComponent("Photo 3.jpg")
        let photo2Contents = try String(contentsOf: photo2URL, encoding: .utf8)
        let photo3Contents = try String(contentsOf: photo3URL, encoding: .utf8)
        #expect(Set(renamedURLs) == Set([photo2URL, photo3URL]))
        #expect(photo2Contents == "one")
        #expect(photo3Contents == "two")
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

    @Test func batchRenameExternalDestinationCollisionLeavesAllOriginalsUntouched() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFile = try temporaryDirectory.createFile(named: "Photo 1.jpg", contents: "one")
        let secondFile = try temporaryDirectory.createFile(named: "Photo 2.jpg", contents: "two")
        _ = try temporaryDirectory.createFile(named: "Photo 3.jpg", contents: "external")

        await #expect(throws: FileOperationError.destinationExists(temporaryDirectory.sourceURL.appendingPathComponent("Photo 3.jpg"))) {
            try await FileOperationService().batchRename(
                items: [firstFile, secondFile],
                baseName: "Photo",
                startingNumber: 2,
                preserveExtensions: true
            )
        }

        let firstContents = try String(contentsOf: firstFile.url, encoding: .utf8)
        let secondContents = try String(contentsOf: secondFile.url, encoding: .utf8)
        let externalContents = try String(
            contentsOf: temporaryDirectory.sourceURL.appendingPathComponent("Photo 3.jpg"),
            encoding: .utf8
        )
        #expect(firstContents == "one")
        #expect(secondContents == "two")
        #expect(externalContents == "external")
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

    @Test func validateTransferRejectsSameSourceAndDestination() throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "same.txt", contents: "same")

        #expect(throws: FileOperationError.cannotReplaceItemWithItself(sourceFile.url)) {
            try FileOperationService.validateTransfer(items: [sourceFile], to: temporaryDirectory.sourceURL)
        }
    }

    @Test func validateTransferRejectsFolderIntoItself() throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let folderURL = try temporaryDirectory.createSourceDirectory(named: "Folder")
        let folderItem = try FileItem(url: folderURL)

        #expect(throws: FileOperationError.cannotPlaceFolderInsideItself(folderURL)) {
            try FileOperationService.validateTransfer(items: [folderItem], to: folderURL)
        }
    }

    @Test func validateTransferRejectsFolderIntoDescendant() throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let folderURL = try temporaryDirectory.createSourceDirectory(named: "Folder")
        let childURL = folderURL.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        let folderItem = try FileItem(url: folderURL)

        #expect(throws: FileOperationError.cannotPlaceFolderInsideItself(folderURL)) {
            try FileOperationService.validateTransfer(items: [folderItem], to: childURL)
        }
    }

    @Test func validateTransferRejectsExistingDestinationCollision() throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "duplicate.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "duplicate.txt", contents: "existing")
        let destinationURL = temporaryDirectory.destinationURL.appendingPathComponent("duplicate.txt")

        #expect(throws: FileOperationError.operationCancelled(destinationURL)) {
            try FileOperationService.validateTransfer(items: [sourceFile], to: temporaryDirectory.destinationURL)
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

    @Test func copyReplaceStagesThenReplacesDestinationWithoutUsingTrash() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "replace.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "replace.txt", contents: "existing")
        let trashService = MockTrashService()

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
        #expect(FileManager.default.fileExists(atPath: sourceFile.url.path))
        #expect(trashService.trashedURLs.isEmpty)
        #expect(try temporaryDirectory.replacementStagingURLs().isEmpty)
    }

    @Test func moveReplaceStagesThenReplacesDestinationAndRemovesSource() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "replace.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "replace.txt", contents: "existing")

        try await FileOperationService().move(
            items: [sourceFile],
            to: temporaryDirectory.destinationURL,
            conflictResolution: .replace
        )

        let replacedContents = try String(
            contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("replace.txt"),
            encoding: .utf8
        )
        #expect(replacedContents == "source")
        #expect(!FileManager.default.fileExists(atPath: sourceFile.url.path))
        #expect(try temporaryDirectory.replacementStagingURLs().isEmpty)
    }

    @Test func copyReplaceStagingFailureLeavesSourceAndDestinationIntact() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "replace.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "replace.txt", contents: "existing")
        let fileSystem = FailingFileSystem(failCopyToReplacementStaging: true)

        do {
            try await FileOperationService(fileSystem: fileSystem).copy(
                items: [sourceFile],
                to: temporaryDirectory.destinationURL,
                conflictResolution: .replace
            )
            Issue.record("Expected copy replace to fail")
        } catch {
            let sourceContents = try String(contentsOf: sourceFile.url, encoding: .utf8)
            let destinationContents = try String(
                contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("replace.txt"),
                encoding: .utf8
            )
            #expect(sourceContents == "source")
            #expect(destinationContents == "existing")
            #expect(try temporaryDirectory.replacementStagingURLs().isEmpty)
        }
    }

    @Test func copyReplaceFinalReplacementFailureCleansStagingAndLeavesDestination() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "replace.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "replace.txt", contents: "existing")
        let fileSystem = FailingFileSystem(failReplacement: true)

        do {
            try await FileOperationService(fileSystem: fileSystem).copy(
                items: [sourceFile],
                to: temporaryDirectory.destinationURL,
                conflictResolution: .replace
            )
            Issue.record("Expected copy replace to fail")
        } catch {
            let sourceContents = try String(contentsOf: sourceFile.url, encoding: .utf8)
            let destinationContents = try String(
                contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("replace.txt"),
                encoding: .utf8
            )
            #expect(sourceContents == "source")
            #expect(destinationContents == "existing")
            #expect(try temporaryDirectory.replacementStagingURLs().isEmpty)
        }
    }

    @Test func moveReplaceStagingFailureLeavesSourceAndDestinationIntact() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "replace.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "replace.txt", contents: "existing")
        let fileSystem = FailingFileSystem(failCopyToReplacementStaging: true)

        do {
            try await FileOperationService(fileSystem: fileSystem).move(
                items: [sourceFile],
                to: temporaryDirectory.destinationURL,
                conflictResolution: .replace
            )
            Issue.record("Expected move replace to fail")
        } catch {
            let sourceContents = try String(contentsOf: sourceFile.url, encoding: .utf8)
            let destinationContents = try String(
                contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("replace.txt"),
                encoding: .utf8
            )
            #expect(sourceContents == "source")
            #expect(destinationContents == "existing")
            #expect(try temporaryDirectory.replacementStagingURLs().isEmpty)
        }
    }

    @Test func moveReplaceSourceCleanupFailureReportsPartialReplacementState() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "replace.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "replace.txt", contents: "existing")
        let fileSystem = FailingFileSystem(failRemoveSourceNamed: sourceFile.url.lastPathComponent)

        do {
            try await FileOperationService(fileSystem: fileSystem).move(
                items: [sourceFile],
                to: temporaryDirectory.destinationURL,
                conflictResolution: .replace
            )
            Issue.record("Expected move replace cleanup to fail")
        } catch {
            let sourceContents = try String(contentsOf: sourceFile.url, encoding: .utf8)
            let destinationContents = try String(
                contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("replace.txt"),
                encoding: .utf8
            )
            #expect(sourceContents == "source")
            #expect(destinationContents == "source")
            #expect(try temporaryDirectory.replacementStagingURLs().isEmpty)
            #expect(
                (error as? LocalizedError)?.errorDescription?
                    .contains("Destination was replaced, but the original item could not be removed") == true
            )
        }
    }

    @Test func selectedItemsWithCaseVariantNamesArePreflightedAsDuplicateDestinations() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFolderURL = try temporaryDirectory.createSourceDirectory(named: "First")
        let secondFolderURL = try temporaryDirectory.createSourceDirectory(named: "Second")
        let firstFile = try temporaryDirectory.createFile(in: firstFolderURL, named: "Report.txt", contents: "first")
        let secondFile = try temporaryDirectory.createFile(in: secondFolderURL, named: "report.txt", contents: "second")

        await #expect(throws: FileOperationError.operationCancelled(temporaryDirectory.destinationURL.appendingPathComponent("report.txt"))) {
            try await FileOperationService().copy(items: [firstFile, secondFile], to: temporaryDirectory.destinationURL)
        }

        #expect(try temporaryDirectory.destinationNames().isEmpty)
    }

    @Test func keepBothReservationAvoidsCaseVariantCopyNames() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let firstFolderURL = try temporaryDirectory.createSourceDirectory(named: "First")
        let secondFolderURL = try temporaryDirectory.createSourceDirectory(named: "Second")
        let firstFile = try temporaryDirectory.createFile(in: firstFolderURL, named: "Report.txt", contents: "first")
        let secondFile = try temporaryDirectory.createFile(in: secondFolderURL, named: "report.txt", contents: "second")
        _ = try temporaryDirectory.createDestinationFile(named: "Report.txt", contents: "existing")

        try await FileOperationService().copy(
            items: [firstFile, secondFile],
            to: temporaryDirectory.destinationURL,
            conflictResolution: .keepBoth
        )

        #expect(try Set(temporaryDirectory.destinationNames()) == Set([
            "Report.txt",
            "Report copy.txt",
            "report copy 2.txt"
        ]))
    }

    @Test func validateTransferRejectsFolderIntoSymlinkedDescendant() throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let folderURL = try temporaryDirectory.createSourceDirectory(named: "Folder")
        let childURL = folderURL.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: false)
        let symlinkURL = temporaryDirectory.rootURL.appendingPathComponent("LinkToChild", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: childURL)
        let folderItem = try FileItem(url: folderURL)

        #expect(throws: FileOperationError.cannotPlaceFolderInsideItself(folderURL)) {
            try FileOperationService.validateTransfer(items: [folderItem], to: symlinkURL)
        }
    }

    @Test func transferConflictPredictionMatchesServiceForSimpleCaseAndEmptyDestinations() async throws {
        let temporaryDirectory = try OperationTestTemporaryDirectory()
        let sourceFile = try temporaryDirectory.createFile(named: "collision.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "collision.txt", contents: "existing")

        #expect(FileOperationService.hasPotentialTransferConflict(items: [sourceFile], to: temporaryDirectory.destinationURL))
        await #expect(throws: FileOperationError.operationCancelled(temporaryDirectory.destinationURL.appendingPathComponent("collision.txt"))) {
            try await FileOperationService().copy(items: [sourceFile], to: temporaryDirectory.destinationURL)
        }

        let clearDestinationURL = temporaryDirectory.rootURL.appendingPathComponent("Clear", isDirectory: true)
        try FileManager.default.createDirectory(at: clearDestinationURL, withIntermediateDirectories: false)
        #expect(!FileOperationService.hasPotentialTransferConflict(items: [sourceFile], to: clearDestinationURL))
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

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var protectedProgresses: [FileOperationProgress] = []

    var progresses: [FileOperationProgress] {
        lock.lock()
        defer { lock.unlock() }

        return protectedProgresses
    }

    func append(_ progress: FileOperationProgress) {
        lock.lock()
        protectedProgresses.append(progress)
        lock.unlock()
    }
}

private final class SimulatedTransferService: FileTransferServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let intermediateByteCount: Int64
    private var protectedCopyCount = 0

    init(intermediateByteCount: Int64) {
        self.intermediateByteCount = intermediateByteCount
    }

    var copyCount: Int {
        lock.withLock { protectedCopyCount }
    }

    func copyItem(
        at sourceURL: URL,
        to destinationURL: URL,
        progressHandler: @escaping @Sendable (Int64) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws {
        lock.withLock { protectedCopyCount += 1 }
        progressHandler(intermediateByteCount)
        if isCancelled() {
            throw CancellationError()
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        let byteCount = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        progressHandler(Int64(byteCount))
    }
}

private final class CancellingTransferService: FileTransferServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let cancelOnCopyNumber: Int
    private var protectedCopyCount = 0

    init(cancelOnCopyNumber: Int) {
        self.cancelOnCopyNumber = cancelOnCopyNumber
    }

    func copyItem(
        at sourceURL: URL,
        to destinationURL: URL,
        progressHandler: @escaping @Sendable (Int64) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws {
        let copyNumber = lock.withLock { () -> Int in
            protectedCopyCount += 1
            return protectedCopyCount
        }

        if copyNumber == cancelOnCopyNumber {
            try Data("partial".utf8).write(to: destinationURL)
            progressHandler(1)
            throw CancellationError()
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        let byteCount = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        progressHandler(Int64(byteCount))
    }
}

private struct FixedVolumeIdentityProvider: VolumeIdentityProviding {
    let isSameVolume: Bool

    func isSameVolume(sourceURL: URL, destinationDirectoryURL: URL) -> Bool {
        isSameVolume
    }
}

private struct FailingArchiveProcessRunner: ArchiveProcessRunning {
    let error: any Error & Sendable
    let partialArchiveContents: String?
    let competingArchiveURL: URL?
    let competingArchiveContents: String?

    func createArchive(from items: [FileItem], at archiveURL: URL) async throws {
        if let partialArchiveContents {
            try partialArchiveContents.write(to: archiveURL, atomically: true, encoding: .utf8)
        }

        if let competingArchiveURL, let competingArchiveContents {
            try competingArchiveContents.write(to: competingArchiveURL, atomically: true, encoding: .utf8)
        }

        throw error
    }
}

private struct LateCollisionArchiveProcessRunner: ArchiveProcessRunning {
    let competingArchiveURL: URL
    let competingArchiveContents: String
    let archiveContents: String

    func createArchive(from items: [FileItem], at archiveURL: URL) async throws {
        try archiveContents.write(to: archiveURL, atomically: true, encoding: .utf8)
        try competingArchiveContents.write(to: competingArchiveURL, atomically: true, encoding: .utf8)
    }
}

private struct SuccessfulArchiveProcessRunner: ArchiveProcessRunning {
    let archiveContents: String

    func createArchive(from items: [FileItem], at archiveURL: URL) async throws {
        try archiveContents.write(to: archiveURL, atomically: true, encoding: .utf8)
    }
}

private func hasTemporaryArchiveArtifacts(in directoryURL: URL) throws -> Bool {
    try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil,
        options: []
    ).contains { $0.lastPathComponent.hasPrefix(".openpane-archive-") }
}

private func zipEntryNames(at archiveURL: URL) throws -> Set<String> {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-Z1", archiveURL.path]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        let reason = String(data: errorData, encoding: .utf8) ?? "Unable to inspect ZIP entries."
        throw NSError(
            domain: "OpenPaneTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: reason]
        )
    }

    let output = String(data: outputData, encoding: .utf8) ?? ""
    return Set(output.split(whereSeparator: \.isNewline).map(String.init))
}

private func extractZip(at archiveURL: URL, to destinationURL: URL) throws {
    let process = Process()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let reason = String(data: errorData, encoding: .utf8) ?? "Unable to extract ZIP archive."
        throw NSError(
            domain: "OpenPaneTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: reason]
        )
    }
}

private final class FailingFileSystem: FileSystemOperating, @unchecked Sendable {
    private let failCopyToReplacementStaging: Bool
    private let failReplacement: Bool
    private let failRemoveSourceNamed: String?
    private let exclusiveMoveError: (any Error & Sendable)?

    init(
        failCopyToReplacementStaging: Bool = false,
        failReplacement: Bool = false,
        failRemoveSourceNamed: String? = nil,
        exclusiveMoveError: (any Error & Sendable)? = nil
    ) {
        self.failCopyToReplacementStaging = failCopyToReplacementStaging
        self.failReplacement = failReplacement
        self.failRemoveSourceNamed = failRemoveSourceNamed
        self.exclusiveMoveError = exclusiveMoveError
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        if failCopyToReplacementStaging && destinationURL.lastPathComponent.hasPrefix(".openpane-replace-") {
            throw NSError(
                domain: "OpenPaneTests",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Simulated staging copy failure"]
            )
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    func moveItemExclusively(at sourceURL: URL, to destinationURL: URL) throws {
        if let exclusiveMoveError {
            throw exclusiveMoveError
        }

        try FileManagerFileSystem().moveItemExclusively(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        if failRemoveSourceNamed == url.lastPathComponent {
            throw NSError(
                domain: "OpenPaneTests",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Simulated source cleanup failure"]
            )
        }

        try FileManager.default.removeItem(at: url)
    }

    func replaceItem(at originalURL: URL, withItemAt replacementURL: URL) throws {
        if failReplacement {
            throw NSError(
                domain: "OpenPaneTests",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Simulated replacement failure"]
            )
        }

        _ = try FileManager.default.replaceItemAt(
            originalURL,
            withItemAt: replacementURL,
            backupItemName: nil,
            options: []
        )
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func fileExists(at url: URL, isDirectory: inout ObjCBool) -> Bool {
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    }

    func isWritableFile(at url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func createFile(at url: URL) -> Bool {
        FileManager.default.createFile(atPath: url.path, contents: Data())
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

    func createFile(in directoryURL: URL, named name: String, contents: String) throws -> FileItem {
        try createFile(at: directoryURL.appendingPathComponent(name), contents: contents)
    }

    func createSourceDirectory(named name: String) throws -> URL {
        let url = sourceURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func destinationNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .sorted()
    }

    func replacementStagingURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix(".openpane-replace-") }
    }

    func transferStagingURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: nil,
            options: []
        ).filter { $0.lastPathComponent.hasPrefix(".openpane-transfer-") }
    }

    private func createFile(at url: URL, contents: String) throws -> FileItem {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return try FileItem(url: url)
    }
}
