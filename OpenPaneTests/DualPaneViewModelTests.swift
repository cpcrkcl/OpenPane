//
//  DualPaneViewModelTests.swift
//  OpenPaneTests
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation
import Testing
@testable import OpenPane

@MainActor
struct DualPaneViewModelTests {
    @Test func defaultsToLeftActivePane() {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        #expect(viewModel.activePaneSide == .left)
        #expect(viewModel.activePane === leftPane)
        #expect(viewModel.inactivePane === rightPane)
    }

    @Test func setActivePaneSwitchesActiveAndInactivePane() {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        viewModel.setActivePane(.right)

        #expect(viewModel.activePaneSide == .right)
        #expect(viewModel.activePane === rightPane)
        #expect(viewModel.inactivePane === leftPane)
    }

    @Test func navigateActivePaneCanOpenMountedVolumeURL() async {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        let volumeURL = URL(filePath: "/Volumes/External", directoryHint: .isDirectory)
        viewModel.setActivePane(.right)

        await viewModel.navigateActivePane(to: volumeURL)

        #expect(leftPane.currentURL == URL(filePath: "/left"))
        #expect(rightPane.currentURL == volumeURL)
    }

    @Test func backAndForwardNavigationRouteToActivePane() async {
        let leftURL = URL(filePath: "/left", directoryHint: .isDirectory)
        let leftChildURL = URL(filePath: "/left/child", directoryHint: .isDirectory)
        let rightURL = URL(filePath: "/right", directoryHint: .isDirectory)
        let rightChildURL = URL(filePath: "/right/child", directoryHint: .isDirectory)
        let leftPane = FilePaneViewModel(currentURL: leftURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: rightURL, fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        await leftPane.setDirectory(leftChildURL)
        await rightPane.setDirectory(rightChildURL)
        viewModel.setActivePane(.right)

        await viewModel.goBackInActivePane()

        #expect(leftPane.currentURL == leftChildURL)
        #expect(rightPane.currentURL == rightURL)

        await viewModel.goForwardInActivePane()

        #expect(leftPane.currentURL == leftChildURL)
        #expect(rightPane.currentURL == rightChildURL)
    }

    @Test func swapPaneLocationsExchangesCurrentURLs() async {
        let leftURL = URL(filePath: "/left")
        let rightURL = URL(filePath: "/right")
        let leftPane = FilePaneViewModel(currentURL: leftURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: rightURL, fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.swapPaneLocations()

        #expect(viewModel.leftPane.currentURL == rightURL)
        #expect(viewModel.rightPane.currentURL == leftURL)
    }

    @Test func moveTabMovesTabBetweenPanesAndActivatesDestination() async {
        let leftURL = URL(filePath: "/left")
        let rightURL = URL(filePath: "/right")
        let leftPane = FilePaneViewModel(currentURL: leftURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: rightURL, fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        await leftPane.newTab()
        let movedTabID = leftPane.activeTabID

        viewModel.moveTab(movedTabID, from: .left, to: .right)

        #expect(leftPane.tabs.count == 1)
        #expect(rightPane.tabs.count == 2)
        #expect(rightPane.activeTabID == movedTabID)
        #expect(rightPane.currentURL == leftURL)
        #expect(viewModel.activePaneSide == .right)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.operationStatusMessage == "Moved tab to right pane.")
    }

    @Test func moveTabShowsErrorWhenMovingOnlySourceTab() {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        viewModel.moveTab(leftPane.activeTabID, from: .left, to: .right)

        #expect(leftPane.tabs.count == 1)
        #expect(rightPane.tabs.count == 1)
        #expect(viewModel.errorMessage == "Each pane needs at least one tab.")
        #expect(viewModel.operationStatusMessage == "Each pane needs at least one tab.")
    }

    @Test func canMoveTabPreventsMovingLastTabBetweenPanes() async {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        #expect(viewModel.canMoveTab(tabID: leftPane.activeTabID, from: .left, to: .right) == false)
        #expect(viewModel.canMoveTab(tabID: leftPane.activeTabID, from: .left, to: .left) == true)

        await leftPane.newTab()

        #expect(viewModel.canMoveTab(tabID: leftPane.activeTabID, from: .left, to: .right) == true)
    }

    @Test func moveTabInsertsAtDestinationIndex() async {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        await leftPane.newTab()
        await rightPane.newTab()
        let movedTabID = leftPane.activeTabID
        let firstRightTabID = rightPane.tabs[0].id
        let secondRightTabID = rightPane.tabs[1].id

        viewModel.moveTab(tabID: movedTabID, from: .left, to: .right, at: 1)

        #expect(leftPane.tabs.count == 1)
        #expect(rightPane.tabs.map(\.id) == [firstRightTabID, movedTabID, secondRightTabID])
        #expect(rightPane.activeTabID == movedTabID)
        #expect(viewModel.activePaneSide == .right)
    }

    @Test func moveTabBetweenPanesPreservesMovedTabState() {
        let sourceURL = URL(filePath: "/source")
        let movedURL = URL(filePath: "/source/Projects")
        let destinationURL = URL(filePath: "/destination")
        let leftPane = FilePaneViewModel(currentURL: sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: destinationURL, fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        let sourceFallbackTab = FilePaneTab(currentURL: sourceURL)
        let movedTab = FilePaneTab(currentURL: movedURL)
        let destinationFirstTab = FilePaneTab(currentURL: destinationURL)
        let destinationSecondTab = FilePaneTab(currentURL: URL(filePath: "/destination/Downloads"))
        leftPane.tabs = [sourceFallbackTab, movedTab]
        leftPane.activeTabID = movedTab.id
        leftPane.currentURL = movedURL
        rightPane.tabs = [destinationFirstTab, destinationSecondTab]
        rightPane.activeTabID = destinationFirstTab.id

        viewModel.moveTab(tabID: movedTab.id, from: .left, to: .right, at: 1)

        #expect(leftPane.tabs.map(\.id) == [sourceFallbackTab.id])
        #expect(leftPane.activeTabID == sourceFallbackTab.id)
        #expect(leftPane.currentURL == sourceURL)
        #expect(rightPane.tabs.map(\.id) == [destinationFirstTab.id, movedTab.id, destinationSecondTab.id])
        #expect(rightPane.activeTabID == movedTab.id)
        #expect(rightPane.currentURL == movedURL)
        #expect(rightPane.tabs[1].currentURL == movedURL)
        #expect(rightPane.tabs[1].title == "Projects")
        #expect(viewModel.activePaneSide == .right)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.operationStatusMessage == "Moved tab to right pane.")
    }

    @Test func moveTabWithinSamePaneReordersTabs() async {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        let firstTabID = leftPane.activeTabID
        await leftPane.newTab()
        let secondTabID = leftPane.activeTabID
        await leftPane.newTab()
        let thirdTabID = leftPane.activeTabID

        viewModel.moveTab(tabID: firstTabID, from: .left, to: .left, at: 2)

        #expect(leftPane.tabs.map(\.id) == [secondTabID, thirdTabID, firstTabID])
        #expect(leftPane.activeTabID == thirdTabID)
        #expect(viewModel.activePaneSide == .left)
    }

    @Test func reorderTabShowsErrorForMissingTab() {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        viewModel.reorderTab(tabID: UUID(), in: .left, toIndex: 0)

        #expect(viewModel.errorMessage == "Tab could not be reordered.")
        #expect(viewModel.operationStatusMessage == "Tab could not be reordered.")
    }

    @Test func tabDragItemEncodesSourceSideTabIDAndCurrentURL() throws {
        let tabID = UUID()
        let currentURL = URL(filePath: "/Users/example/Documents")
        let item = FilePaneTabDragItem(tabID: tabID, sourcePaneSide: .left, currentURL: currentURL)

        let data = try #require(item.encodedData)
        let decodedItem = try #require(FilePaneTabDragItem.decoded(from: data))

        #expect(decodedItem.tabID == tabID)
        #expect(decodedItem.sourcePaneSide == .left)
        #expect(decodedItem.currentURL == currentURL)
    }

    @Test func copySelectionToOtherPaneShowsErrorWhenNothingIsSelected() async {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.copySelectionToOtherPane()

        #expect(viewModel.errorMessage == "Select one or more items to copy.")
        #expect(viewModel.operationStatusMessage == "Select one or more items to copy.")
        #expect(viewModel.isPerformingOperation == false)
    }

    @Test func copySelectionToOtherPaneCopiesToInactivePaneAndRefreshesIt() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "copy.txt", contents: "hello")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: FileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        leftPane.selectedItems = [sourceItem]

        await viewModel.copySelectionToOtherPane()

        let copiedURL = temporaryDirectory.destinationURL.appendingPathComponent("copy.txt")
        let copiedContents = try String(contentsOf: copiedURL, encoding: .utf8)
        #expect(copiedContents == "hello")
        #expect(rightPane.items.map(\.name) == ["copy.txt"])
        #expect(leftPane.selectedItems == [sourceItem])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isPerformingOperation == false)
        #expect(viewModel.operationStatusMessage == "Copied 1 item to Destination.")
    }

    @Test func partialCopyFailureRefreshesDestinationAndReportsCompletedCount() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createSourceFile(named: "first.txt", contents: "first")
        let secondItem = try temporaryDirectory.createSourceFile(named: "second.txt", contents: "second")
        let leftPane = FilePaneViewModel(
            currentURL: temporaryDirectory.sourceURL,
            fileBrowserService: FileBrowserService()
        )
        let rightPane = FilePaneViewModel(
            currentURL: temporaryDirectory.destinationURL,
            fileBrowserService: FileBrowserService()
        )
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: PartialTransferFileOperationService(operation: .copy)
        )
        leftPane.items = [firstItem, secondItem]
        leftPane.selectedItems = [firstItem, secondItem]

        await viewModel.copySelectionToOtherPane()

        #expect(rightPane.items.map(\.name) == ["first.txt"])
        #expect(leftPane.items.map(\.name) == ["first.txt", "second.txt"])
        #expect(viewModel.operationStatusMessage == "Copy failed. 1 of 2 completed.")
        #expect(viewModel.errorMessage?.contains("Simulated failure") == true)
        #expect(viewModel.isPerformingOperation == false)
    }

    @Test func moveSelectionToOtherPaneShowsErrorWhenNothingIsSelected() async {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.moveSelectionToOtherPane()

        #expect(viewModel.errorMessage == "Select one or more items to move.")
        #expect(viewModel.operationStatusMessage == "Select one or more items to move.")
        #expect(viewModel.isPerformingOperation == false)
    }

    @Test func moveSelectionToOtherPaneMovesFileRefreshesBothAndClearsSelection() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "move.txt", contents: "goodbye")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: FileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: FileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        leftPane.selectedItems = [sourceItem]

        await viewModel.moveSelectionToOtherPane()

        let movedURL = temporaryDirectory.destinationURL.appendingPathComponent("move.txt")
        let movedContents = try String(contentsOf: movedURL, encoding: .utf8)
        #expect(movedContents == "goodbye")
        #expect(!FileManager.default.fileExists(atPath: sourceItem.url.path))
        #expect(leftPane.items.isEmpty)
        #expect(rightPane.items.map(\.name) == ["move.txt"])
        #expect(leftPane.selectedItems.isEmpty)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isPerformingOperation == false)
        #expect(viewModel.operationStatusMessage == "Moved 1 item to Destination.")
    }

    @Test func partialMoveFailureRefreshesBothPanesAndReportsCompletedCount() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createSourceFile(named: "first.txt", contents: "first")
        let secondItem = try temporaryDirectory.createSourceFile(named: "second.txt", contents: "second")
        let leftPane = FilePaneViewModel(
            currentURL: temporaryDirectory.sourceURL,
            fileBrowserService: FileBrowserService()
        )
        let rightPane = FilePaneViewModel(
            currentURL: temporaryDirectory.destinationURL,
            fileBrowserService: FileBrowserService()
        )
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: PartialTransferFileOperationService(operation: .move)
        )
        leftPane.items = [firstItem, secondItem]
        leftPane.selectedItems = [firstItem, secondItem]

        await viewModel.moveSelectionToOtherPane()

        #expect(leftPane.items.map(\.name) == ["second.txt"])
        #expect(rightPane.items.map(\.name) == ["first.txt"])
        #expect(viewModel.operationStatusMessage == "Move failed. 1 of 2 completed.")
        #expect(viewModel.errorMessage?.contains("Simulated failure") == true)
        #expect(viewModel.isPerformingOperation == false)
    }

    @Test func moveSelectionUpdatesOriginalActivePaneWhenFocusChangesDuringOperation() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "move.txt", contents: "move me")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let fileOperationService = SuspendingMoveFileOperationService()
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )
        leftPane.items = [sourceItem]
        leftPane.selectedItems = [sourceItem]

        let operationTask = Task {
            await viewModel.moveSelectionToOtherPane()
        }

        await fileOperationService.waitForMoveToStart()
        viewModel.setActivePane(.right)
        fileOperationService.resumeMove()
        await operationTask.value

        #expect(viewModel.activePaneSide == .right)
        #expect(leftPane.selectedItems.isEmpty)
        #expect(rightPane.selectedItems.isEmpty)
        #expect(fileOperationService.movedItems == [sourceItem])
        #expect(fileOperationService.moveDestinationURL == temporaryDirectory.destinationURL)
    }

    @Test func operationStateTracksRunningItemCount() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createSourceFile(named: "first.txt", contents: "one")
        let secondItem = try temporaryDirectory.createSourceFile(named: "second.txt", contents: "two")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let fileOperationService = SuspendingMoveFileOperationService()
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )
        leftPane.selectedItems = [firstItem, secondItem]

        let operationTask = Task {
            await viewModel.moveSelectionToOtherPane()
        }

        await fileOperationService.waitForMoveToStart()

        #expect(viewModel.operationState.isRunning)
        #expect(viewModel.operationState.totalItemCount == 2)
        #expect(viewModel.operationState.completedItemCount == 0)
        #expect(viewModel.operationState.isCancellable)

        fileOperationService.resumeMove()
        await operationTask.value

        #expect(viewModel.operationState == .idle)
        #expect(viewModel.isPerformingOperation == false)
    }

    @Test func operationStateAdvancesWhenServiceReportsProgress() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createSourceFile(named: "first.txt", contents: "one")
        let secondItem = try temporaryDirectory.createSourceFile(named: "second.txt", contents: "two")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let fileOperationService = SuspendingMoveFileOperationService()
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )
        leftPane.selectedItems = [firstItem, secondItem]

        let operationTask = Task {
            await viewModel.moveSelectionToOtherPane()
        }

        await fileOperationService.waitForMoveToStart()
        fileOperationService.reportMoveProgress(completedItemCount: 1, totalItemCount: 2)
        await Task.yield()

        #expect(viewModel.operationState.isRunning)
        #expect(viewModel.operationState.completedItemCount == 1)
        #expect(viewModel.operationState.totalItemCount == 2)

        fileOperationService.resumeMove()
        await operationTask.value

        #expect(viewModel.operationState == .idle)
    }

    @Test func cancelCurrentOperationCancelsRunningOperationWithoutFileFailure() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "cancel.txt", contents: "stop")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let fileOperationService = SuspendingMoveFileOperationService()
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )
        leftPane.selectedItems = [sourceItem]

        let operationTask = Task {
            await viewModel.moveSelectionToOtherPane()
        }

        await fileOperationService.waitForMoveToStart()
        viewModel.cancelCurrentOperation()
        await operationTask.value

        #expect(viewModel.operationState == .idle)
        #expect(viewModel.isPerformingOperation == false)
        #expect(viewModel.operationStatusMessage == "Operation cancelled.")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func pasteIntoPaneCopiesPasteboardFileURLsToTargetPane() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "paste.txt", contents: "paste me")
        let workspaceService = PasteboardWorkspaceService(fileURLs: [sourceItem.url])
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(
            currentURL: temporaryDirectory.destinationURL,
            fileBrowserService: FileBrowserService(),
            workspaceService: workspaceService
        )
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.pasteIntoPane(rightPane)

        let pastedURL = temporaryDirectory.destinationURL.appendingPathComponent("paste.txt")
        let pastedContents = try String(contentsOf: pastedURL, encoding: .utf8)
        #expect(pastedContents == "paste me")
        #expect(rightPane.items.map(\.name) == ["paste.txt"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.operationStatusMessage == "Pasted 1 item.")
    }

    @Test func copyDroppedFileURLsCopiesIntoTargetDirectoryAndRefreshesTargetPane() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "drop.txt", contents: "drop me")
        let targetFolderURL = temporaryDirectory.destinationURL.appendingPathComponent("Target Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: targetFolderURL, withIntermediateDirectories: true)
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: FileBrowserService())
        let fileOperationService = MockFileOperationService()
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )

        await viewModel.copyDroppedFileURLs(
            [sourceItem.url],
            sourcePaneSide: .left,
            to: targetFolderURL,
            in: .right
        )

        #expect(fileOperationService.copiedItems == [sourceItem])
        #expect(fileOperationService.copyDestinationURL == targetFolderURL)
        #expect(fileOperationService.copyConflictResolution == .cancel)
        #expect(rightPane.items.map(\.name) == ["Target Folder"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.operationStatusMessage == "Copied 1 item to Target Folder.")
    }

    @Test func moveDroppedFileURLsMovesIntoTargetDirectoryAndRefreshesPanes() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "move-drop.txt", contents: "move me")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let fileOperationService = MockFileOperationService()
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )

        await viewModel.moveDroppedFileURLs(
            [sourceItem.url],
            sourcePaneSide: .left,
            to: temporaryDirectory.destinationURL,
            in: .right
        )

        #expect(fileOperationService.movedItems == [sourceItem])
        #expect(fileOperationService.moveDestinationURL == temporaryDirectory.destinationURL)
        #expect(fileOperationService.moveConflictResolution == .cancel)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.operationStatusMessage == "Moved 1 item to Destination.")
    }

    @Test func copyDroppedFileURLsCopiesFromRightToLeft() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createDestinationFile(named: "right-drop.txt", contents: "right to left")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let fileOperationService = MockFileOperationService()
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )

        await viewModel.copyDroppedFileURLs(
            [sourceItem.url],
            sourcePaneSide: .right,
            to: temporaryDirectory.sourceURL,
            in: .left
        )

        #expect(fileOperationService.copiedItems == [sourceItem])
        #expect(fileOperationService.copyDestinationURL == temporaryDirectory.sourceURL)
        #expect(fileOperationService.copyConflictResolution == .cancel)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.operationStatusMessage == "Copied 1 item to Source.")
    }

    @Test func copyDroppedFileURLsDeduplicatesStandardizedURLs() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "dedupe.txt", contents: "once")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let fileOperationService = MockFileOperationService()
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )

        await viewModel.copyDroppedFileURLs(
            [
                sourceItem.url,
                temporaryDirectory.sourceURL.appendingPathComponent(".").appendingPathComponent("dedupe.txt")
            ],
            sourcePaneSide: .left,
            to: temporaryDirectory.destinationURL,
            in: .right
        )

        #expect(fileOperationService.copiedItems == [sourceItem])
        #expect(viewModel.operationStatusMessage == "Copied 1 item to Destination.")
    }

    @Test func copyDroppedFileURLsCancelsCollisionWithoutOverwriting() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "collision.txt", contents: "source")
        _ = try temporaryDirectory.createDestinationFile(named: "collision.txt", contents: "existing")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: FileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: FileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.copyDroppedFileURLs(
            [sourceItem.url],
            sourcePaneSide: .left,
            to: temporaryDirectory.destinationURL,
            in: .right
        )

        let existingContents = try String(
            contentsOf: temporaryDirectory.destinationURL.appendingPathComponent("collision.txt"),
            encoding: .utf8
        )
        #expect(existingContents == "existing")
        #expect(viewModel.errorMessage == "Operation cancelled because an item named collision.txt already exists.")
        #expect(viewModel.operationStatusMessage == "Drop copy failed.")
    }

    @Test func moveDroppedFileURLsFromRightToLeftRefreshesBothPanes() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createDestinationFile(named: "right-move.txt", contents: "move left")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: FileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: FileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.moveDroppedFileURLs(
            [sourceItem.url],
            sourcePaneSide: .right,
            to: temporaryDirectory.sourceURL,
            in: .left
        )

        let movedURL = temporaryDirectory.sourceURL.appendingPathComponent("right-move.txt")
        let movedContents = try String(contentsOf: movedURL, encoding: .utf8)
        #expect(movedContents == "move left")
        #expect(!FileManager.default.fileExists(atPath: sourceItem.url.path))
        #expect(leftPane.items.map(\.name) == ["right-move.txt"])
        #expect(rightPane.items.isEmpty)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.operationStatusMessage == "Moved 1 item to Source.")
    }

    @Test func droppedFileOperationRejectsSameDirectoryDrop() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "same-place.txt", contents: "same")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let fileOperationService = MockFileOperationService()
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )

        await viewModel.copyDroppedFileURLs(
            [sourceItem.url],
            sourcePaneSide: .left,
            to: temporaryDirectory.sourceURL,
            in: .left
        )

        #expect(fileOperationService.copiedItems.isEmpty)
        #expect(viewModel.errorMessage == "Items are already in Source.")
        #expect(viewModel.operationStatusMessage == "Items are already in Source.")
    }

    @Test func trashSelectionInActivePaneShowsErrorWhenNothingIsSelected() async {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let fileOperationService = MockFileOperationService()
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )

        await viewModel.trashSelectionInActivePane()

        #expect(viewModel.errorMessage == "Select one or more items to move to Trash.")
        #expect(viewModel.operationStatusMessage == "Select one or more items to move to Trash.")
        #expect(viewModel.isPerformingOperation == false)
        #expect(fileOperationService.trashedItems.isEmpty)
    }

    @Test func trashSelectionInActivePaneTrashesItemsRefreshesActivePaneAndClearsSelection() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "trash.txt", contents: "trash me")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let fileOperationService = MockFileOperationService()
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )
        leftPane.items = [sourceItem]
        leftPane.selectedItems = [sourceItem]

        await viewModel.trashSelectionInActivePane()

        #expect(fileOperationService.trashedItems == [sourceItem])
        #expect(leftPane.items.isEmpty)
        #expect(leftPane.selectedItems.isEmpty)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isPerformingOperation == false)
        #expect(viewModel.operationStatusMessage == "Moved 1 item to Trash.")
    }

    @Test func trashSelectionInActivePaneSurfacesErrors() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "trash.txt", contents: "trash me")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: FileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let fileOperationService = MockFileOperationService(error: FileOperationError.trashFailed(sourceItem.url, "Trash is unavailable"))
        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            fileOperationService: fileOperationService
        )
        leftPane.items = [sourceItem]
        leftPane.selectedItems = [sourceItem]

        await viewModel.trashSelectionInActivePane()

        #expect(fileOperationService.trashedItems == [sourceItem])
        #expect(leftPane.items.map(\.name) == [sourceItem.name])
        #expect(leftPane.selectedItems.map(\.name) == [sourceItem.name])
        #expect(viewModel.errorMessage == "Could not move trash.txt to Trash: Trash is unavailable")
        #expect(viewModel.isPerformingOperation == false)
        #expect(viewModel.operationStatusMessage == "Move to Trash failed.")
    }

    @Test func createFolderInActivePaneCreatesFolderAndRefreshesActivePane() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: FileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.createFolderInActivePane(named: "Projects")

        let folderURL = temporaryDirectory.sourceURL.appendingPathComponent("Projects", isDirectory: true)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(leftPane.items.map(\.name) == ["Projects"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isPerformingOperation == false)
        #expect(viewModel.operationStatusMessage == "Created folder.")
    }

    @Test func createFolderInActivePaneShowsErrorForEmptyName() async {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.createFolderInActivePane(named: "")

        #expect(viewModel.errorMessage == "Name cannot be empty.")
        #expect(viewModel.isPerformingOperation == false)
        #expect(viewModel.operationStatusMessage == "New folder failed.")
    }

    @Test func renameSelectedItemShowsErrorWhenNothingIsSelected() async {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.renameSelectedItem(to: "Renamed.txt")

        #expect(viewModel.errorMessage == "Select one item to rename.")
        #expect(viewModel.operationStatusMessage == "Select one item to rename.")
        #expect(viewModel.isPerformingOperation == false)
    }

    @Test func renameSelectedItemShowsErrorWhenMultipleItemsAreSelected() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createSourceFile(named: "First.txt", contents: "one")
        let secondItem = try temporaryDirectory.createSourceFile(named: "Second.txt", contents: "two")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        leftPane.selectedItems = [firstItem, secondItem]

        await viewModel.renameSelectedItem(to: "Renamed.txt")

        #expect(viewModel.errorMessage == "Select only one item to rename.")
        #expect(viewModel.operationStatusMessage == "Select only one item to rename.")
        #expect(viewModel.isPerformingOperation == false)
    }

    @Test func renameSelectedItemRenamesFileRefreshesActivePaneAndClearsSelection() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "Original.txt", contents: "hello")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: FileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        leftPane.selectedItems = [sourceItem]

        await viewModel.renameSelectedItem(to: "Renamed.txt")

        let renamedURL = temporaryDirectory.sourceURL.appendingPathComponent("Renamed.txt")
        let renamedContents = try String(contentsOf: renamedURL, encoding: .utf8)
        #expect(renamedContents == "hello")
        #expect(!FileManager.default.fileExists(atPath: sourceItem.url.path))
        #expect(leftPane.items.map(\.name) == ["Renamed.txt"])
        #expect(leftPane.selectedItems.isEmpty)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isPerformingOperation == false)
        #expect(viewModel.operationStatusMessage == "Renamed Original.txt.")
    }

    @Test func batchRenameSelectedItemsShowsErrorWhenLessThanTwoItemsAreSelected() async {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.batchRenameSelectedItems(baseName: "Photo", startingNumber: 1)

        #expect(viewModel.errorMessage == "Select multiple items to batch rename.")
        #expect(viewModel.operationStatusMessage == "Select multiple items to batch rename.")
    }

    @Test func batchRenameSelectedItemsRenamesFilesRefreshesActivePaneAndClearsSelection() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createSourceFile(named: "IMG_1.jpg", contents: "one")
        let secondItem = try temporaryDirectory.createSourceFile(named: "IMG_2.jpg", contents: "two")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: FileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        leftPane.selectedItems = [firstItem, secondItem]

        await viewModel.batchRenameSelectedItems(baseName: "Photo", startingNumber: 1)

        #expect(FileManager.default.fileExists(atPath: temporaryDirectory.sourceURL.appendingPathComponent("Photo 1.jpg").path))
        #expect(FileManager.default.fileExists(atPath: temporaryDirectory.sourceURL.appendingPathComponent("Photo 2.jpg").path))
        #expect(leftPane.selectedItems.isEmpty)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.operationStatusMessage == "Renamed 2 items.")
    }
}

nonisolated private struct EmptyFileBrowserService: FileBrowserServicing {
    nonisolated func contentsOfDirectory(at url: URL, includeHiddenFiles: Bool) async throws -> [FileItem] {
        []
    }
}

@MainActor
private final class PasteboardWorkspaceService: WorkspaceServicing, @unchecked Sendable {
    let fileURLs: [URL]

    init(fileURLs: [URL]) {
        self.fileURLs = fileURLs
    }

    func open(url: URL) -> Bool { true }
    func appsAvailableToOpen(url: URL) -> [ApplicationOption] { [] }
    func open(url: URL, withApplication applicationURL: URL) async throws {}
    func chooseApplicationAndOpen(url: URL) {}
    func revealInFinder(urls: [URL]) {}
    func share(urls: [URL]) throws {}
    func copyFileURLs(_ urls: [URL]) {}
    func fileURLsForPasteboard() -> [URL] { fileURLs }
    func copyPath(url: URL) {}
    func copyText(_ text: String) {}
}

private final class MockFileOperationService: FileOperationServicing, @unchecked Sendable {
    private let error: Error?
    private let queue = DispatchQueue(label: "OpenPaneTests.MockFileOperationService")
    private var protectedTrashedItems: [FileItem] = []
    private var protectedCopiedItems: [FileItem] = []
    private var protectedCopyDestinationURL: URL?
    private var protectedCopyConflictResolution: FileConflictResolution?
    private var protectedMovedItems: [FileItem] = []
    private var protectedMoveDestinationURL: URL?
    private var protectedMoveConflictResolution: FileConflictResolution?

    init(error: Error? = nil) {
        self.error = error
    }

    var trashedItems: [FileItem] {
        queue.sync {
            protectedTrashedItems
        }
    }

    var copiedItems: [FileItem] {
        queue.sync {
            protectedCopiedItems
        }
    }

    var copyDestinationURL: URL? {
        queue.sync {
            protectedCopyDestinationURL
        }
    }

    var copyConflictResolution: FileConflictResolution? {
        queue.sync {
            protectedCopyConflictResolution
        }
    }

    var movedItems: [FileItem] {
        queue.sync {
            protectedMovedItems
        }
    }

    var moveDestinationURL: URL? {
        queue.sync {
            protectedMoveDestinationURL
        }
    }

    var moveConflictResolution: FileConflictResolution? {
        queue.sync {
            protectedMoveConflictResolution
        }
    }

    func copy(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution,
        progressHandler: FileOperationProgressHandler?
    ) async throws {
        progressHandler?(
            FileOperationProgress(
                completedItemCount: 0,
                totalItemCount: items.count
            )
        )

        queue.sync {
            protectedCopiedItems.append(contentsOf: items)
            protectedCopyDestinationURL = destinationDirectory
            protectedCopyConflictResolution = conflictResolution
        }

        if let error {
            throw error
        }

        progressHandler?(
            FileOperationProgress(
                completedItemCount: items.count,
                totalItemCount: items.count
            )
        )
    }

    func move(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution,
        progressHandler: FileOperationProgressHandler?
    ) async throws {
        progressHandler?(
            FileOperationProgress(
                completedItemCount: 0,
                totalItemCount: items.count
            )
        )

        queue.sync {
            protectedMovedItems.append(contentsOf: items)
            protectedMoveDestinationURL = destinationDirectory
            protectedMoveConflictResolution = conflictResolution
        }

        if let error {
            throw error
        }

        progressHandler?(
            FileOperationProgress(
                completedItemCount: items.count,
                totalItemCount: items.count
            )
        )
    }

    func trash(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws {
        progressHandler?(
            FileOperationProgress(
                completedItemCount: 0,
                totalItemCount: items.count
            )
        )

        queue.sync {
            protectedTrashedItems.append(contentsOf: items)
        }

        if let error {
            throw error
        }

        progressHandler?(
            FileOperationProgress(
                completedItemCount: items.count,
                totalItemCount: items.count
            )
        )
    }

    func duplicate(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws {
        progressHandler?(
            FileOperationProgress(
                completedItemCount: items.count,
                totalItemCount: items.count
            )
        )
    }

    func compress(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws -> URL {
        progressHandler?(
            FileOperationProgress(
                completedItemCount: items.count,
                totalItemCount: items.count
            )
        )

        return URL(filePath: "/archive.zip")
    }

    func rename(item: FileItem, to newName: String) async throws -> URL {
        item.url.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: item.isDirectory)
    }

    func batchRename(
        items: [FileItem],
        baseName: String,
        startingNumber: Int,
        preserveExtensions: Bool
    ) async throws -> [URL] {
        []
    }

    func createFolder(named name: String, in directory: URL) async throws -> URL {
        directory.appendingPathComponent(name, isDirectory: true)
    }

    func createFile(named name: String, in directory: URL) async throws -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }
}

private final class PartialTransferFileOperationService: FileOperationServicing, @unchecked Sendable {
    enum Operation {
        case copy
        case move
    }

    private let operation: Operation

    init(operation: Operation) {
        self.operation = operation
    }

    func copy(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution,
        progressHandler: FileOperationProgressHandler?
    ) async throws {
        guard operation == .copy, let firstItem = items.first else {
            return
        }

        progressHandler?(FileOperationProgress(completedItemCount: 0, totalItemCount: items.count))
        try FileManager.default.copyItem(
            at: firstItem.url,
            to: destinationDirectory.appendingPathComponent(firstItem.name, isDirectory: firstItem.isDirectory)
        )
        progressHandler?(FileOperationProgress(completedItemCount: 1, totalItemCount: items.count))
        throw FileOperationError.operationFailed("copy", items.dropFirst().first?.url ?? firstItem.url, "Simulated failure")
    }

    func move(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution,
        progressHandler: FileOperationProgressHandler?
    ) async throws {
        guard operation == .move, let firstItem = items.first else {
            return
        }

        progressHandler?(FileOperationProgress(completedItemCount: 0, totalItemCount: items.count))
        try FileManager.default.moveItem(
            at: firstItem.url,
            to: destinationDirectory.appendingPathComponent(firstItem.name, isDirectory: firstItem.isDirectory)
        )
        progressHandler?(FileOperationProgress(completedItemCount: 1, totalItemCount: items.count))
        throw FileOperationError.operationFailed("move", items.dropFirst().first?.url ?? firstItem.url, "Simulated failure")
    }

    func trash(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws {}
    func duplicate(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws {}
    func compress(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws -> URL {
        URL(filePath: "/archive.zip")
    }
    func rename(item: FileItem, to newName: String) async throws -> URL { item.url }
    func batchRename(
        items: [FileItem],
        baseName: String,
        startingNumber: Int,
        preserveExtensions: Bool
    ) async throws -> [URL] { [] }
    func createFolder(named name: String, in directory: URL) async throws -> URL { directory }
    func createFile(named name: String, in directory: URL) async throws -> URL { directory }
}

private final class SuspendingMoveFileOperationService: FileOperationServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var didStartMove = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeMoveContinuation: CheckedContinuation<Void, Error>?
    private var protectedMovedItems: [FileItem] = []
    private var protectedMoveDestinationURL: URL?
    private var protectedMoveProgressHandler: FileOperationProgressHandler?

    var movedItems: [FileItem] {
        lock.lock()
        defer { lock.unlock() }

        return protectedMovedItems
    }

    var moveDestinationURL: URL? {
        lock.lock()
        defer { lock.unlock() }

        return protectedMoveDestinationURL
    }

    func copy(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution,
        progressHandler: FileOperationProgressHandler?
    ) async throws {}

    func move(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution,
        progressHandler: FileOperationProgressHandler?
    ) async throws {
        progressHandler?(
            FileOperationProgress(
                completedItemCount: 0,
                totalItemCount: items.count
            )
        )

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                protectedMovedItems = items
                protectedMoveDestinationURL = destinationDirectory
                protectedMoveProgressHandler = progressHandler
                resumeMoveContinuation = continuation
                didStartMove = true
                let waiters = startWaiters
                startWaiters = []
                lock.unlock()

                waiters.forEach { $0.resume() }
            }
        } onCancel: {
            resumeMove(throwing: CancellationError())
        }

        progressHandler?(
            FileOperationProgress(
                completedItemCount: items.count,
                totalItemCount: items.count
            )
        )
    }

    func trash(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws {}

    func duplicate(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws {}

    func compress(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws -> URL {
        URL(filePath: "/archive.zip")
    }

    func rename(item: FileItem, to newName: String) async throws -> URL {
        item.url.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: item.isDirectory)
    }

    func batchRename(
        items: [FileItem],
        baseName: String,
        startingNumber: Int,
        preserveExtensions: Bool
    ) async throws -> [URL] {
        []
    }

    func createFolder(named name: String, in directory: URL) async throws -> URL {
        directory.appendingPathComponent(name, isDirectory: true)
    }

    func createFile(named name: String, in directory: URL) async throws -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    func waitForMoveToStart() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didStartMove {
                lock.unlock()
                continuation.resume()
            } else {
                startWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func resumeMove() {
        resumeMove(throwing: nil)
    }

    func reportMoveProgress(completedItemCount: Int, totalItemCount: Int) {
        lock.lock()
        let progressHandler = protectedMoveProgressHandler
        lock.unlock()

        progressHandler?(
            FileOperationProgress(
                completedItemCount: completedItemCount,
                totalItemCount: totalItemCount
            )
        )
    }

    private func resumeMove(throwing error: Error?) {
        lock.lock()
        let continuation = resumeMoveContinuation
        resumeMoveContinuation = nil
        lock.unlock()

        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}

private struct DualPaneTestTemporaryDirectory {
    let rootURL: URL
    let sourceURL: URL
    let destinationURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneDualPaneTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceURL = rootURL.appendingPathComponent("Source", isDirectory: true)
        destinationURL = rootURL.appendingPathComponent("Destination", isDirectory: true)

        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    }

    func createSourceFile(named name: String, contents: String) throws -> FileItem {
        let fileURL = sourceURL.appendingPathComponent(name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileItem(url: fileURL)
    }

    func createDestinationFile(named name: String, contents: String) throws -> FileItem {
        let fileURL = destinationURL.appendingPathComponent(name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileItem(url: fileURL)
    }
}
