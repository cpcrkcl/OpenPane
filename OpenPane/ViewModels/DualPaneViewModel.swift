//
//  DualPaneViewModel.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Combine
import Foundation

enum PaneSide: Equatable, Sendable {
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

    func copySelectionToOtherPane() async {
        guard let selectedItems = selectedItemsForOperation(verb: "copy") else {
            return
        }

        await performOperation(
            statusMessage: "Copying \(Self.itemCountDescription(selectedItems)) to \(Self.displayName(for: inactivePane.currentURL))...",
            successMessage: "Copied \(Self.itemCountDescription(selectedItems)) to \(Self.displayName(for: inactivePane.currentURL)).",
            failureMessage: "Copy failed."
        ) {
            try await fileOperationService.copy(items: selectedItems, to: inactivePane.currentURL)
            await inactivePane.refresh()
        }
    }

    func moveSelectionToOtherPane() async {
        guard let selectedItems = selectedItemsForOperation(verb: "move") else {
            return
        }

        await performOperation(
            statusMessage: "Moving \(Self.itemCountDescription(selectedItems)) to \(Self.displayName(for: inactivePane.currentURL))...",
            successMessage: "Moved \(Self.itemCountDescription(selectedItems)) to \(Self.displayName(for: inactivePane.currentURL)).",
            failureMessage: "Move failed."
        ) {
            try await fileOperationService.move(items: selectedItems, to: inactivePane.currentURL)
            activePane.selectedItems = []
            await refreshBoth()
        }
    }

    func trashSelectionInActivePane() async {
        guard let selectedItems = selectedItemsForOperation(verb: "move to Trash") else {
            return
        }

        await performOperation(
            statusMessage: "Moving \(Self.itemCountDescription(selectedItems)) to Trash...",
            successMessage: "Moved \(Self.itemCountDescription(selectedItems)) to Trash.",
            failureMessage: "Move to Trash failed."
        ) {
            try await fileOperationService.trash(items: selectedItems)
            activePane.selectedItems = []
            await activePane.refresh()
        }
    }

    func createFolderInActivePane(named name: String) async {
        await performOperation(
            statusMessage: "Creating folder...",
            successMessage: "Created folder.",
            failureMessage: "New folder failed."
        ) {
            _ = try await fileOperationService.createFolder(named: name, in: activePane.currentURL)
            await activePane.refresh()
        }
    }

    func renameSelectedItem(to newName: String) async {
        let selectedItems = Array(activePane.selectedItems)

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
            activePane.selectedItems = []
            await activePane.refresh()
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

    private func selectedItemsForOperation(verb: String) -> [FileItem]? {
        let selectedItems = Array(activePane.selectedItems)

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

    private static func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
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
