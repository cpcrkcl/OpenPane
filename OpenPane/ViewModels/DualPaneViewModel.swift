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

nonisolated enum FileDropOperation: Equatable, Sendable {
    case copy
    case move
}

nonisolated enum DefaultFileDropAction: String, CaseIterable, Identifiable, Sendable {
    case copy
    case ask
    case move

    static let userDefaultsKey = "OpenPaneDefaultFileDropAction"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy:
            "Copy"
        case .ask:
            "Ask"
        case .move:
            "Move"
        }
    }
}

nonisolated enum FileDropPreparationDecision: Equatable, Sendable {
    case perform(FileDropOperation)
    case ask
    case resolveConflicts(FileDropOperation)

    static func forOrdinaryDrop(
        defaultAction: DefaultFileDropAction,
        hasPotentialConflict: Bool
    ) -> Self {
        guard defaultAction != .ask else {
            return .ask
        }

        let operation: FileDropOperation = defaultAction == .copy ? .copy : .move
        return hasPotentialConflict ? .resolveConflicts(operation) : .perform(operation)
    }
}

nonisolated struct FileOperationState: Equatable, Sendable {
    let isRunning: Bool
    let label: String
    let completedItemCount: Int
    let totalItemCount: Int
    let isCancellable: Bool

    static let idle = FileOperationState(
        isRunning: false,
        label: "",
        completedItemCount: 0,
        totalItemCount: 0,
        isCancellable: false
    )

    static func running(
        label: String,
        totalItemCount: Int,
        isCancellable: Bool = true
    ) -> FileOperationState {
        FileOperationState(
            isRunning: true,
            label: label,
            completedItemCount: 0,
            totalItemCount: max(0, totalItemCount),
            isCancellable: isCancellable
        )
    }

    func updatingProgress(_ progress: FileOperationProgress) -> FileOperationState {
        FileOperationState(
            isRunning: isRunning,
            label: label,
            completedItemCount: progress.completedItemCount,
            totalItemCount: progress.totalItemCount,
            isCancellable: isCancellable
        )
    }
}

private final class OperationProgressSink: @unchecked Sendable {
    @MainActor private weak var viewModel: DualPaneViewModel?
    private let lock = NSLock()
    nonisolated(unsafe) private var protectedLatestProgress: FileOperationProgress?

    @MainActor
    init(viewModel: DualPaneViewModel) {
        self.viewModel = viewModel
    }

    nonisolated func report(_ progress: FileOperationProgress) {
        lock.withLock {
            protectedLatestProgress = progress
        }
        Task { @MainActor [weak self] in
            self?.viewModel?.applyOperationProgress(progress)
        }
    }

    nonisolated var latestProgress: FileOperationProgress? {
        lock.withLock {
            protectedLatestProgress
        }
    }
}

@MainActor
final class DualPaneViewModel: ObservableObject {
    @Published var leftPane: FilePaneViewModel
    @Published var rightPane: FilePaneViewModel
    @Published var activePaneSide: PaneSide
    @Published var errorMessage: String?
    @Published var isPerformingOperation: Bool
    @Published var operationStatusMessage: String?
    @Published var splitLeftPaneFraction: Double?
    @Published private(set) var operationState: FileOperationState

    private let fileOperationService: any FileOperationServicing
    private var paneObservationCancellables: Set<AnyCancellable> = []
    private var currentOperationTask: Task<Void, Error>?

    var activePane: FilePaneViewModel {
        activePaneSide == .left ? leftPane : rightPane
    }

    var inactivePane: FilePaneViewModel {
        activePaneSide == .left ? rightPane : leftPane
    }

    convenience init() {
        let defaultPaneURLs = Self.defaultPaneURLs()
        self.init(
            leftPane: FilePaneViewModel(currentURL: defaultPaneURLs.left),
            rightPane: FilePaneViewModel(currentURL: defaultPaneURLs.right)
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
        self.splitLeftPaneFraction = nil
        self.operationState = .idle
        self.fileOperationService = fileOperationService
        observePaneChanges()
    }

    func setActivePane(_ side: PaneSide) {
        activePaneSide = side
    }

    func showStatusMessage(_ message: String) {
        operationStatusMessage = message
    }

    func navigateActivePane(to url: URL) async {
        await activePane.setDirectory(url)
    }

    func cancelCurrentOperation() {
        guard operationState.isRunning,
              operationState.isCancellable else {
            return
        }

        operationStatusMessage = "Cancelling operation..."
        currentOperationTask?.cancel()
    }

    func pane(for side: PaneSide) -> FilePaneViewModel {
        side == .left ? leftPane : rightPane
    }

    func refreshBoth() async {
        await leftPane.refresh()
        await rightPane.refresh()
    }

    func goBackInActivePane() async {
        let pane = activePane
        await pane.goBack()
    }

    func goForwardInActivePane() async {
        let pane = activePane
        await pane.goForward()
    }

    func swapPaneLocations() async {
        let leftURL = leftPane.currentURL
        let rightURL = rightPane.currentURL

        await leftPane.setDirectory(rightURL)
        await rightPane.setDirectory(leftURL)
    }

    func sessionState() -> SessionState {
        SessionState(
            leftPane: leftPane.sessionState(),
            rightPane: rightPane.sessionState(),
            activePaneSide: activePaneSide,
            splitLeftPaneFraction: splitLeftPaneFraction
        )
    }

    static func restoring(
        _ sessionState: SessionState?,
        fallbackURL: URL? = nil,
        fileManager: FileManager = .default,
        fileOperationService: any FileOperationServicing = FileOperationService()
    ) -> DualPaneViewModel {
        let defaultPaneURLs = Self.defaultPaneURLs()
        let resolvedFallbackURL = fallbackURL ?? defaultPaneURLs.left

        guard let sessionState else {
            return DualPaneViewModel(
                leftPane: FilePaneViewModel(currentURL: resolvedFallbackURL),
                rightPane: FilePaneViewModel(currentURL: defaultPaneURLs.right),
                fileOperationService: fileOperationService
            )
        }

        let leftPane = FilePaneViewModel(currentURL: resolvedFallbackURL)
        let rightPane = FilePaneViewModel(currentURL: resolvedFallbackURL)
        leftPane.applySessionState(
            sessionState.leftPane,
            fallbackURL: resolvedFallbackURL,
            fileManager: fileManager
        )
        rightPane.applySessionState(
            sessionState.rightPane,
            fallbackURL: resolvedFallbackURL,
            fileManager: fileManager
        )

        let viewModel = DualPaneViewModel(
            leftPane: leftPane,
            rightPane: rightPane,
            activePaneSide: sessionState.activePaneSide,
            fileOperationService: fileOperationService
        )
        viewModel.splitLeftPaneFraction = sessionState.splitLeftPaneFraction
        return viewModel
    }

    func moveTab(_ tabID: FilePaneTab.ID, from sourceSide: PaneSide, to destinationSide: PaneSide) {
        moveTab(tabID: tabID, from: sourceSide, to: destinationSide, at: nil)
    }

    func canMoveTab(tabID: FilePaneTab.ID, from sourceSide: PaneSide, to destinationSide: PaneSide) -> Bool {
        let sourcePane = pane(for: sourceSide)
        let destinationPane = pane(for: destinationSide)

        guard sourcePane.containsTab(tabID) else {
            return false
        }

        if sourceSide == destinationSide {
            return true
        }

        return sourcePane.canDetachTab(tabID) && !destinationPane.containsTab(tabID)
    }

    func moveTab(tabID: FilePaneTab.ID, from sourceSide: PaneSide, to destinationSide: PaneSide, at destinationIndex: Int?) {
        if sourceSide == destinationSide {
            guard let destinationIndex else {
                return
            }

            reorderTab(tabID: tabID, in: sourceSide, toIndex: destinationIndex)
            return
        }

        guard canMoveTab(tabID: tabID, from: sourceSide, to: destinationSide) else {
            showTabMoveError(tabID: tabID, from: sourceSide, to: destinationSide)
            return
        }

        let sourcePane = pane(for: sourceSide)
        let destinationPane = pane(for: destinationSide)

        guard let tab = sourcePane.detachTab(tabID) else {
            showTabMoveError(tabID: tabID, from: sourceSide, to: destinationSide)
            return
        }

        destinationPane.receiveTab(tab, at: destinationIndex)
        activePaneSide = destinationSide
        errorMessage = nil
        operationStatusMessage = "Moved tab to \(Self.paneDescription(destinationSide)) pane."
    }

    func reorderTab(tabID: FilePaneTab.ID, in paneSide: PaneSide, toIndex: Int) {
        let pane = pane(for: paneSide)

        guard pane.containsTab(tabID) else {
            errorMessage = "Tab could not be reordered."
            operationStatusMessage = errorMessage
            return
        }

        pane.reorderTab(tabID, toIndex: toIndex)
        activePaneSide = paneSide
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
            failureMessage: "Copy failed.",
            totalItemCount: selectedItems.count,
            operationWithProgress: { [self] progressHandler in
            try await performReconciledMutation {
                try await fileOperationService.copy(
                    items: selectedItems,
                    to: destinationURL,
                    conflictResolution: conflictResolution,
                    progressHandler: progressHandler
                )
            } reconcile: {
                await refreshPanes(showingAnyOf: [destinationURL])
            }
        })
    }

    func copyDroppedFileURLs(
        _ fileURLs: [URL],
        sourcePaneSide: PaneSide?,
        to targetDirectory: URL,
        in targetPaneSide: PaneSide,
        conflictResolution: FileConflictResolution = .cancel
    ) async {
        await performDroppedFileOperation(
            .copy,
            fileURLs,
            sourcePaneSide: sourcePaneSide,
            to: targetDirectory,
            in: targetPaneSide,
            conflictResolution: conflictResolution
        )
    }

    func moveDroppedFileURLs(
        _ fileURLs: [URL],
        sourcePaneSide: PaneSide?,
        to targetDirectory: URL,
        in targetPaneSide: PaneSide,
        conflictResolution: FileConflictResolution = .cancel
    ) async {
        await performDroppedFileOperation(
            .move,
            fileURLs,
            sourcePaneSide: sourcePaneSide,
            to: targetDirectory,
            in: targetPaneSide,
            conflictResolution: conflictResolution
        )
    }

    private func performDroppedFileOperation(
        _ operation: FileDropOperation,
        _ fileURLs: [URL],
        sourcePaneSide: PaneSide?,
        to targetDirectory: URL,
        in targetPaneSide: PaneSide,
        conflictResolution: FileConflictResolution
    ) async {
        let uniqueFileURLs = Self.uniqueFileURLs(fileURLs)

        guard !uniqueFileURLs.isEmpty else {
            errorMessage = "No file URLs found to drop."
            operationStatusMessage = errorMessage
            return
        }

        guard !Self.containsItemAlreadyInTargetDirectory(uniqueFileURLs, targetDirectory: targetDirectory) else {
            errorMessage = "Items are already in \(targetDirectory.openPaneDisplayName)."
            operationStatusMessage = errorMessage
            return
        }

        let targetPane = pane(for: targetPaneSide)
        let targetName = targetDirectory.openPaneDisplayName
        let operationVerb = operation == .copy ? "Copying" : "Moving"
        let successVerb = operation == .copy ? "Copied" : "Moved"
        let failureMessage = operation == .copy ? "Drop copy failed." : "Drop move failed."

        await performOperation(
            statusMessage: "\(operationVerb) \(Self.itemCountDescription(uniqueFileURLs.count)) to \(targetName)...",
            successMessage: "\(successVerb) \(Self.itemCountDescription(uniqueFileURLs.count)) to \(targetName).",
            failureMessage: failureMessage,
            totalItemCount: uniqueFileURLs.count,
            operationWithProgress: { [self] progressHandler in
            let items = try uniqueFileURLs.map { try FileItem(url: $0) }

            try await performReconciledMutation {
                switch operation {
                case .copy:
                    try await fileOperationService.copy(
                        items: items,
                        to: targetDirectory,
                        conflictResolution: conflictResolution,
                        progressHandler: progressHandler
                    )
                case .move:
                    try await fileOperationService.move(
                        items: items,
                        to: targetDirectory,
                        conflictResolution: conflictResolution,
                        progressHandler: progressHandler
                    )
                }
            } reconcile: {
                targetPane.markTabsDirty(showingAnyOf: [targetDirectory])
                await targetPane.refresh()

                if let sourcePaneSide {
                    let sourcePane = pane(for: sourcePaneSide)
                    sourcePane.markTabsDirty(showingAnyOf: uniqueFileURLs.map { $0.deletingLastPathComponent() })
                    if operation == .move || sourcePane.currentURL == targetDirectory {
                        await sourcePane.refresh()
                    }
                }
            }
        })
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
            failureMessage: "Move failed.",
            totalItemCount: selectedItems.count,
            operationWithProgress: { [self] progressHandler in
            let sourceURL = sourcePane.currentURL
            try await performReconciledMutation {
                try await fileOperationService.move(
                    items: selectedItems,
                    to: destinationURL,
                    conflictResolution: conflictResolution,
                    progressHandler: progressHandler
                )
                sourcePane.selectedItems = []
            } reconcile: {
                await refreshPanes(showingAnyOf: [sourceURL, destinationURL])
            }
        })
    }

    func trashSelectionInActivePane() async {
        let sourcePane = activePane

        guard let selectedItems = selectedItemsForOperation(in: sourcePane, verb: "move to Trash") else {
            return
        }

        await performOperation(
            statusMessage: "Moving \(Self.itemCountDescription(selectedItems)) to Trash...",
            successMessage: "Moved \(Self.itemCountDescription(selectedItems)) to Trash.",
            failureMessage: "Move to Trash failed.",
            totalItemCount: selectedItems.count,
            operationWithProgress: { [self] progressHandler in
            let sourceURL = sourcePane.currentURL
            try await performReconciledMutation {
                try await fileOperationService.trash(items: selectedItems, progressHandler: progressHandler)
                sourcePane.selectedItems = []
            } reconcile: {
                await refreshPanes(showingAnyOf: [sourceURL])
            }
        })
    }

    func duplicateSelectionInActivePane() async {
        let sourcePane = activePane

        guard let selectedItems = selectedItemsForOperation(in: sourcePane, verb: "duplicate") else {
            return
        }

        await duplicate(items: selectedItems, in: sourcePane)
    }

    func duplicateForContextMenu(clickedItem: FileItem, in pane: FilePaneViewModel) async {
        let targetItems = pane.contextMenuTargetItems(clickedItem: clickedItem)
        await duplicate(items: targetItems, in: pane)
    }

    func compressForContextMenu(clickedItem: FileItem, in pane: FilePaneViewModel) async {
        let targetItems = pane.contextMenuTargetItems(clickedItem: clickedItem)
        await compress(items: targetItems, in: pane)
    }

    func pasteIntoPane(_ pane: FilePaneViewModel) async {
        let fileURLs = pane.fileURLsAvailableToPaste()

        guard !fileURLs.isEmpty else {
            errorMessage = "Nothing to paste."
            operationStatusMessage = errorMessage
            return
        }

        await performOperation(
            statusMessage: "Pasting \(Self.itemCountDescription(fileURLs.count))...",
            successMessage: "Pasted \(Self.itemCountDescription(fileURLs.count)).",
            failureMessage: "Paste failed.",
            totalItemCount: fileURLs.count,
            operationWithProgress: { [self] progressHandler in
            let items = try fileURLs.map { try FileItem(url: $0) }
            let destinationURL = pane.currentURL
            try await performReconciledMutation {
                try await fileOperationService.copy(
                    items: items,
                    to: destinationURL,
                    conflictResolution: .cancel,
                    progressHandler: progressHandler
                )
            } reconcile: {
                await refreshPanes(showingAnyOf: [destinationURL])
            }
        })
    }

    func createFolderInActivePane(named name: String) async {
        let sourcePane = activePane
        let currentURL = sourcePane.currentURL

        await performOperation(
            statusMessage: "Creating folder...",
            successMessage: "Created folder.",
            failureMessage: "New folder failed.",
            totalItemCount: 1
        ) { [self] in
            try await performReconciledMutation {
                _ = try await fileOperationService.createFolder(named: name, in: currentURL)
            } reconcile: {
                await refreshPanes(showingAnyOf: [currentURL])
            }
        }
    }

    func createFileInActivePane(named name: String) async {
        let sourcePane = activePane
        let currentURL = sourcePane.currentURL

        await performOperation(
            statusMessage: "Creating file...",
            successMessage: "Created file.",
            failureMessage: "New file failed.",
            totalItemCount: 1
        ) { [self] in
            try await performReconciledMutation {
                _ = try await fileOperationService.createFile(named: name, in: currentURL)
            } reconcile: {
                await refreshPanes(showingAnyOf: [currentURL])
            }
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
            failureMessage: "Rename failed.",
            totalItemCount: 1
        ) { [self] in
            let sourceURL = sourcePane.currentURL
            try await performReconciledMutation {
                _ = try await fileOperationService.rename(item: selectedItem, to: newName)
                sourcePane.selectedItems = []
            } reconcile: {
                await refreshPanes(showingAnyOf: [sourceURL])
            }
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
            failureMessage: "Batch rename failed.",
            totalItemCount: selectedItems.count
        ) { [self] in
            let sourceURL = sourcePane.currentURL
            try await performReconciledMutation {
                _ = try await fileOperationService.batchRename(
                    items: selectedItems,
                    baseName: baseName,
                    startingNumber: startingNumber,
                    preserveExtensions: true
                )
                sourcePane.selectedItems = []
            } reconcile: {
                await refreshPanes(showingAnyOf: [sourceURL])
            }
        }
    }

    private func duplicate(items: [FileItem], in pane: FilePaneViewModel) async {
        await performOperation(
            statusMessage: "Duplicating \(Self.itemCountDescription(items))...",
            successMessage: "Duplicated \(Self.itemCountDescription(items)).",
            failureMessage: "Duplicate failed.",
            totalItemCount: items.count,
            operationWithProgress: { [self] progressHandler in
            let directoryURL = pane.currentURL
            try await performReconciledMutation {
                try await fileOperationService.duplicate(items: items, progressHandler: progressHandler)
            } reconcile: {
                await refreshPanes(showingAnyOf: [directoryURL])
            }
        })
    }

    private func compress(items: [FileItem], in pane: FilePaneViewModel) async {
        await performOperation(
            statusMessage: "Compressing \(Self.itemCountDescription(items))...",
            successMessage: "Created archive.",
            failureMessage: "Compress failed.",
            totalItemCount: items.count,
            operationWithProgress: { [self] progressHandler in
            let directoryURL = pane.currentURL
            try await performReconciledMutation {
                _ = try await fileOperationService.compress(items: items, progressHandler: progressHandler)
            } reconcile: {
                await refreshPanes(showingAnyOf: [directoryURL])
            }
        })
    }

    private func performOperation(
        statusMessage: String,
        successMessage: String,
        failureMessage: String,
        totalItemCount: Int,
        isCancellable: Bool = true,
        operation: @escaping () async throws -> Void
    ) async {
        await performOperation(
            statusMessage: statusMessage,
            successMessage: successMessage,
            failureMessage: failureMessage,
            totalItemCount: totalItemCount,
            isCancellable: isCancellable,
            operationWithProgress: { _ in
                try await operation()
            }
        )
    }

    private func performOperation(
        statusMessage: String,
        successMessage: String,
        failureMessage: String,
        totalItemCount: Int,
        isCancellable: Bool = true,
        operationWithProgress operation: @escaping (@escaping FileOperationProgressHandler) async throws -> Void
    ) async {
        guard !isPerformingOperation else {
            return
        }

        let progressSink = OperationProgressSink(viewModel: self)
        let progressHandler: FileOperationProgressHandler = { [progressSink] progress in
            progressSink.report(progress)
        }

        isPerformingOperation = true
        operationState = .running(
            label: statusMessage,
            totalItemCount: totalItemCount,
            isCancellable: isCancellable
        )
        operationStatusMessage = statusMessage
        errorMessage = nil
        let operationTask = Task { @MainActor in
            try await operation(progressHandler)
        }
        currentOperationTask = operationTask

        defer {
            currentOperationTask = nil
            operationState = .idle
            isPerformingOperation = false
        }

        do {
            try await operationTask.value
            operationStatusMessage = successMessage
        } catch is CancellationError {
            operationStatusMessage = "Operation cancelled."
            errorMessage = nil
        } catch {
            operationStatusMessage = Self.failureStatusMessage(
                failureMessage,
                progress: progressSink.latestProgress
            )
            errorMessage = Self.userReadableError(for: error)
        }
    }

    private func performReconciledMutation(
        operation: () async throws -> Void,
        reconcile: () async -> Void
    ) async throws {
        do {
            try await operation()
        } catch {
            await reconcile()
            throw error
        }

        await reconcile()
    }

    fileprivate func applyOperationProgress(_ progress: FileOperationProgress) {
        guard operationState.isRunning else {
            return
        }

        guard operationState.completedItemCount != progress.completedItemCount ||
              operationState.totalItemCount != progress.totalItemCount else {
            return
        }

        operationState = operationState.updatingProgress(progress)
    }

    private func selectedItemsForOperation(in pane: FilePaneViewModel, verb: String) -> [FileItem]? {
        let orderedSelectedItems = pane.orderedSelectedItems
        let selectedItems = orderedSelectedItems.isEmpty
            ? pane.selectedItems.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            : orderedSelectedItems

        guard !selectedItems.isEmpty else {
            errorMessage = "Select one or more items to \(verb)."
            operationStatusMessage = errorMessage
            return nil
        }

        return selectedItems
    }

    private func refreshPanes(showingAnyOf directoryURLs: [URL]) async {
        let affectedDirectories = Set(directoryURLs.map(\.standardizedFileURL))
        var refreshedPaneIDs: Set<ObjectIdentifier> = []

        for pane in [leftPane, rightPane] {
            pane.markTabsDirty(showingAnyOf: directoryURLs)
        }

        for pane in [leftPane, rightPane] {
            let paneID = ObjectIdentifier(pane)

            guard !refreshedPaneIDs.contains(paneID),
                  affectedDirectories.contains(pane.currentURL.standardizedFileURL) else {
                continue
            }

            refreshedPaneIDs.insert(paneID)
            await pane.refresh()
        }
    }

    private func showTabMoveError(tabID: FilePaneTab.ID, from sourceSide: PaneSide, to destinationSide: PaneSide) {
        let sourcePane = pane(for: sourceSide)
        let destinationPane = pane(for: destinationSide)

        if sourceSide != destinationSide,
           sourcePane.containsTab(tabID),
           sourcePane.tabs.count == 1 {
            errorMessage = "Each pane needs at least one tab."
        } else if sourceSide != destinationSide,
                  destinationPane.containsTab(tabID) {
            errorMessage = "That tab is already open in the destination pane."
        } else {
            errorMessage = "Tab could not be moved."
        }

        operationStatusMessage = errorMessage
    }

    private static func itemCountDescription(_ items: [FileItem]) -> String {
        itemCountDescription(items.count)
    }

    private static func itemCountDescription(_ count: Int) -> String {
        let itemText = count == 1 ? "item" : "items"
        return "\(count) \(itemText)"
    }

    private static func failureStatusMessage(
        _ failureMessage: String,
        progress: FileOperationProgress?
    ) -> String {
        guard let progress,
              progress.completedItemCount > 0,
              progress.totalItemCount > progress.completedItemCount else {
            return failureMessage
        }

        return "\(failureMessage) \(progress.completedItemCount) of \(progress.totalItemCount) completed."
    }

    private static func uniqueFileURLs(_ urls: [URL]) -> [URL] {
        var seenURLs: Set<URL> = []

        return urls.filter { url in
            let standardizedURL = url
                .resolvingSymlinksInPath()
                .standardizedFileURL

            guard !seenURLs.contains(standardizedURL) else {
                return false
            }

            seenURLs.insert(standardizedURL)
            return true
        }
    }

    private static func containsItemAlreadyInTargetDirectory(_ urls: [URL], targetDirectory: URL) -> Bool {
        let standardizedTargetDirectory = targetDirectory.standardizedFileURL

        return urls.contains { url in
            url
                .deletingLastPathComponent()
                .standardizedFileURL == standardizedTargetDirectory
        }
    }

    private static func paneDescription(_ side: PaneSide) -> String {
        switch side {
        case .left:
            return "left"
        case .right:
            return "right"
        }
    }

    private func observePaneChanges() {
        paneObservationCancellables.removeAll()

        leftPane.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &paneObservationCancellables)

        rightPane.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &paneObservationCancellables)
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

    private static func defaultPaneURLs() -> (left: URL, right: URL) {
        if let uiTestingRootURL {
            return (
                uiTestingRootURL.appendingPathComponent("Left", isDirectory: true),
                uiTestingRootURL.appendingPathComponent("Right", isDirectory: true)
            )
        }

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        return (homeURL, defaultRightPaneURL(fallbackURL: homeURL))
    }

    private static var uiTestingRootURL: URL? {
        let processInfo = ProcessInfo.processInfo
        guard processInfo.arguments.contains("-ui-testing"),
              let rootPath = processInfo.environment["OPENPANE_UI_TEST_ROOT"],
              !rootPath.isEmpty else {
            return nil
        }

        return URL(filePath: rootPath, directoryHint: .isDirectory)
    }

    private static func defaultRightPaneURL(fallbackURL homeURL: URL) -> URL {
        let downloadsURL = homeURL.appendingPathComponent("Downloads", isDirectory: true)
        var isDirectory: ObjCBool = false

        if FileManager.default.fileExists(atPath: downloadsURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return downloadsURL
        }

        return homeURL
    }
}
