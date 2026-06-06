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

        errorMessage = nil

        do {
            try await fileOperationService.copy(items: selectedItems, to: inactivePane.currentURL)
            await inactivePane.refresh()
        } catch {
            errorMessage = Self.userReadableError(for: error)
        }
    }

    func moveSelectionToOtherPane() async {
        guard let selectedItems = selectedItemsForOperation(verb: "move") else {
            return
        }

        errorMessage = nil

        do {
            try await fileOperationService.move(items: selectedItems, to: inactivePane.currentURL)
            activePane.selectedItems = []
            await refreshBoth()
        } catch {
            errorMessage = Self.userReadableError(for: error)
        }
    }

    func createFolderInActivePane(named name: String) async {
        errorMessage = nil

        do {
            _ = try await fileOperationService.createFolder(named: name, in: activePane.currentURL)
            await activePane.refresh()
        } catch {
            errorMessage = Self.userReadableError(for: error)
        }
    }

    private func selectedItemsForOperation(verb: String) -> [FileItem]? {
        let selectedItems = Array(activePane.selectedItems)

        guard !selectedItems.isEmpty else {
            errorMessage = "Select one or more items to \(verb)."
            return nil
        }

        return selectedItems
    }

    private static func userReadableError(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
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
