//
//  DualPaneViewModel.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Combine
import Foundation

nonisolated enum PaneSide: Codable, Equatable, Hashable, Sendable {
    case left
    case right
}

@MainActor
final class DualPaneViewModel: ObservableObject {
    @Published var leftPane: FilePaneViewModel
    @Published var rightPane: FilePaneViewModel
    @Published var activePaneSide: PaneSide
    @Published var errorMessage: String?
    @Published var isPerformingOperation: Bool
    @Published var operationStatusMessage: String?

    private let fileOperationService: any FileOperationServicing

    var activePane: FilePaneViewModel {
        activePaneSide == .left ? leftPane : rightPane
    }

    var inactivePane: FilePaneViewModel {
        activePaneSide == .left ? rightPane : leftPane
    }

    convenience init() {
        self.init(
            leftPane: FilePaneViewModel(currentURL: FileManager.default.homeDirectoryForCurrentUser),
            rightPane: FilePaneViewModel(currentURL: Self.defaultRightPaneURL)
        )
    }

    init(
        leftPane: FilePaneViewModel,
        rightPane: FilePaneViewModel,
        activePaneSide: PaneSide = .left,
        fileOperationService: any FileOperationServicing = FileOperationService()
    ) {
        self.leftPane = leftPane
        self.rightPane = rightPane
        self.activePaneSide = activePaneSide
        self.errorMessage = nil
        self.isPerformingOperation = false
        self.operationStatusMessage = nil
        self.fileOperationService = fileOperationService
    }

    func setActivePane(_ side: PaneSide) {
        activePaneSide = side
    }

    func showStatusMessage(_ message: String) {
        operationStatusMessage = message
    }

    func pane(for side: PaneSide) -> FilePaneViewModel {
        side == .left ? leftPane : rightPane
    }

    func refreshBoth() async {
        await leftPane.refresh()
        await rightPane.refresh()
    }

    func swapPaneLocations() async {
        let leftURL = leftPane.currentURL
        let rightURL = rightPane.currentURL

        await leftPane.setDirectory(rightURL)
        await rightPane.setDirectory(leftURL)
    }

    func moveTab(_ tabID: FilePaneTab.ID, from sourceSide: PaneSide, to destinationSide: PaneSide) {
        guard sourceSide != destinationSide else {
            return
        }

        let sourcePane = pane(for: sourceSide)
        let destinationPane = pane(for: destinationSide)

        guard let tab = sourcePane.detachTab(tabID) else {
            errorMessage = "Each pane needs at least one tab."
            operationStatusMessage = errorMessage
            return
        }

        destinationPane.receiveTab(tab)
        activePaneSide = destinationSide
    }

    func copySelectionToOtherPane(conflictResolution: FileConflictResolution = .cancel) async {
        let sourcePane = activePane
        let destinationPane = inactivePane
        let destinationURL = destinationPane.currentURL

        guard let selectedItems = selectedItemsForOperation(in: sourcePane, verb: "copy") else {
            return
        }

        await performOperation(
            statusMessage: "Copying \(Self.itemCountDescription(selectedItems)) to \(destinationURL.openPaneDisplayName)...",
            successMessage: "Copied \(Self.itemCountDescription(selectedItems)) to \(destinationURL.openPaneDisplayName).",
            failureMessage: "Copy failed."
        ) {
            try await fileOperationService.copy(
                items: selectedItems,
                to: destinationURL,
                conflictResolution: conflictResolution
            )
            await destinationPane.refresh()
        }
    }

    func moveSelectionToOtherPane(conflictResolution: FileConflictResolution = .cancel) async {
        let sourcePane = activePane
        let destinationPane = inactivePane
        let destinationURL = destinationPane.currentURL

        guard let selectedItems = selectedItemsForOperation(in: sourcePane, verb: "move") else {
            return
        }

        await performOperation(
            statusMessage: "Moving \(Self.itemCountDescription(selectedItems)) to \(destinationURL.openPaneDisplayName)...",
            successMessage: "Moved \(Self.itemCountDescription(selectedItems)) to \(destinationURL.openPaneDisplayName).",
            failureMessage: "Move failed."
        ) {
            try await fileOperationService.move(
                items: selectedItems,
                to: destinationURL,
                conflictResolution: conflictResolution
            )
            sourcePane.selectedItems = []
            await sourcePane.refresh()
            await destinationPane.refresh()
        }
    }

    func trashSelectionInActivePane() async {
        let sourcePane = activePane

        guard let selectedItems = selectedItemsForOperation(in: sourcePane, verb: "move to Trash") else {
            return
        }

        await performOperation(
            statusMessage: "Moving \(Self.itemCountDescription(selectedItems)) to Trash...",
            successMessage: "Moved \(Self.itemCountDescription(selectedItems)) to Trash.",
            failureMessage: "Move to Trash failed."
        ) {
            try await fileOperationService.trash(items: selectedItems)
            sourcePane.selectedItems = []
            await sourcePane.refresh()
        }
    }

    func createFolderInActivePane(named name: String) async {
        let sourcePane = activePane
        let currentURL = sourcePane.currentURL

        await performOperation(
            statusMessage: "Creating folder...",
            successMessage: "Created folder.",
            failureMessage: "New folder failed."
        ) {
            _ = try await fileOperationService.createFolder(named: name, in: currentURL)
            await sourcePane.refresh()
        }
    }

    func createFileInActivePane(named name: String) async {
        let sourcePane = activePane
        let currentURL = sourcePane.currentURL

        await performOperation(
            statusMessage: "Creating file...",
            successMessage: "Created file.",
            failureMessage: "New file failed."
        ) {
            _ = try await fileOperationService.createFile(named: name, in: currentURL)
            await sourcePane.refresh()
        }
    }

    func renameSelectedItem(to newName: String) async {
        let sourcePane = activePane
        let selectedItems = Array(sourcePane.selectedItems)

        guard selectedItems.count == 1, let selectedItem = selectedItems.first else {
            errorMessage = selectedItems.isEmpty
                ? "Select one item to rename."
                : "Select only one item to rename."
            operationStatusMessage = errorMessage
            return
        }

        await performOperation(
            statusMessage: "Renaming \(selectedItem.name)...",
            successMessage: "Renamed \(selectedItem.name).",
            failureMessage: "Rename failed."
        ) {
            _ = try await fileOperationService.rename(item: selectedItem, to: newName)
            sourcePane.selectedItems = []
            await sourcePane.refresh()
        }
    }

    func batchRenameSelectedItems(baseName: String, startingNumber: Int) async {
        let sourcePane = activePane
        let selectedItems = Array(sourcePane.selectedItems)

        guard selectedItems.count > 1 else {
            errorMessage = "Select multiple items to batch rename."
            operationStatusMessage = errorMessage
            return
        }

        await performOperation(
            statusMessage: "Renaming \(Self.itemCountDescription(selectedItems))...",
            successMessage: "Renamed \(Self.itemCountDescription(selectedItems)).",
            failureMessage: "Batch rename failed."
        ) {
            _ = try await fileOperationService.batchRename(
                items: selectedItems,
                baseName: baseName,
                startingNumber: startingNumber,
                preserveExtensions: true
            )
            sourcePane.selectedItems = []
            await sourcePane.refresh()
        }
    }

    private func performOperation(
        statusMessage: String,
        successMessage: String,
        failureMessage: String,
        operation: () async throws -> Void
    ) async {
        guard !isPerformingOperation else {
            return
        }

        isPerformingOperation = true
        operationStatusMessage = statusMessage
        errorMessage = nil

        defer {
            isPerformingOperation = false
        }

        do {
            try await operation()
            operationStatusMessage = successMessage
        } catch {
            operationStatusMessage = failureMessage
            errorMessage = Self.userReadableError(for: error)
        }
    }

    private func selectedItemsForOperation(in pane: FilePaneViewModel, verb: String) -> [FileItem]? {
        let selectedItems = Array(pane.selectedItems)

        guard !selectedItems.isEmpty else {
            errorMessage = "Select one or more items to \(verb)."
            operationStatusMessage = errorMessage
            return nil
        }

        return selectedItems
    }

    private static func itemCountDescription(_ items: [FileItem]) -> String {
        let itemText = items.count == 1 ? "item" : "items"
        return "\(items.count) \(itemText)"
    }

    private static func userReadableError(for error: Error) -> String {
        if let operationError = error as? FileOperationError,
           let description = operationError.errorDescription {
            return description
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteNoPermissionError {
            return "Permission denied."
        }

        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
            return "The item could not be found."
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return "The operation could not be completed."
    }

    private static var defaultRightPaneURL: URL {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let downloadsURL = homeURL.appendingPathComponent("Downloads", isDirectory: true)
        var isDirectory: ObjCBool = false

        if FileManager.default.fileExists(atPath: downloadsURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return downloadsURL
        }

        return homeURL
    }
}
