//
//  DualPaneView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import AppKit
import Combine
import SwiftUI

struct DualPaneView: View {
    @ObservedObject var viewModel: DualPaneViewModel
    @EnvironmentObject private var keyboardShortcutStore: KeyboardShortcutStore
    @AppStorage(DefaultFileDropAction.userDefaultsKey) private var defaultFileDropActionRawValue = DefaultFileDropAction.copy.rawValue

    @State private var newFolderName = "Untitled Folder"
    @State private var newFileName = "Untitled.txt"
    @State private var renameItemName = ""
    @State private var batchRenameBaseName = "Item"
    @State private var batchRenameStartingNumber = 1
    @State private var activeSheet: ActiveSheet?
    @State private var isShowingTrashConfirmation = false
    @State private var trashConfirmationItemCount = 0
    @State private var pendingConflictOperation: PendingConflictOperation?
    @State private var pendingFileDrop: PendingFileDrop?
    @State private var leftPaneWidth: CGFloat?
    @State private var isCommandPalettePresented = false
    @FocusState private var focusedSheetField: SheetField?

    private enum ActiveSheet: Identifiable {
        case newFolder
        case newFile
        case rename
        case batchRename

        var id: String {
            switch self {
            case .newFolder:
                "newFolder"
            case .newFile:
                "newFile"
            case .rename:
                "rename"
            case .batchRename:
                "batchRename"
            }
        }
    }

    private enum PendingConflictOperation {
        case copySelection
        case moveSelection
        case fileDrop(PendingFileDrop, FileDropOperation)
    }

    private struct PendingFileDrop: Identifiable {
        let id = UUID()
        let fileURLs: [URL]
        let sourcePaneSide: PaneSide?
        let targetDirectory: URL
        let targetPaneSide: PaneSide
    }

    private enum SheetField: Hashable {
        case newFolderName
        case newFileName
        case renameItemName
        case batchRenameBaseName
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar
                    .padding(12)

                horizontalDivider

                paneSplit
                .padding(12)
                .background(CatppuccinMochaTheme.appBackground)

                horizontalDivider

                statusBar
            }

            if isCommandPalettePresented {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isCommandPalettePresented = false
                    }

                CommandPaletteView(
                    commands: commandPaletteCommands,
                    isPresented: $isCommandPalettePresented
                )
                .transition(.scale(scale: 0.98).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .background(CatppuccinMochaTheme.windowBackground)
        .animation(.easeOut(duration: 0.12), value: isCommandPalettePresented)
        .onReceive(NotificationCenter.default.publisher(for: .openCommandPalette)) { _ in
            isCommandPalettePresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchActivePane)) { _ in
            switchActivePane()
        }
        .alert(
            "OpenPane Couldn’t Complete the Operation",
            isPresented: Binding {
                viewModel.errorMessage != nil
            } set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        ) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newFolder:
                newFolderSheet
            case .newFile:
                newFileSheet
            case .rename:
                renameSheet
            case .batchRename:
                batchRenameSheet
            }
        }
        .confirmationDialog(
            "Move to Trash?",
            isPresented: $isShowingTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Task {
                    await viewModel.trashSelectionInActivePane()
                }
            }
            .disabled(viewModel.isPerformingOperation)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(trashConfirmationMessage)
        }
        .confirmationDialog(
            "File Already Exists",
            isPresented: Binding {
                pendingConflictOperation != nil
            } set: { isPresented in
                if !isPresented {
                    pendingConflictOperation = nil
                }
            },
            titleVisibility: .visible
        ) {
            Button("Keep Both") {
                runPendingConflictOperation(with: .keepBoth)
            }

            Button("Replace Existing", role: .destructive) {
                runPendingConflictOperation(with: .replace)
            }

            Button("Skip Existing") {
                runPendingConflictOperation(with: .skip)
            }

            Button("Cancel", role: .cancel) {
                pendingConflictOperation = nil
            }
        } message: {
            Text(pendingConflictMessage)
        }
        .confirmationDialog(
            "Drop Items",
            isPresented: Binding {
                pendingFileDrop != nil
            } set: { isPresented in
                if !isPresented {
                    pendingFileDrop = nil
                }
            },
            titleVisibility: .visible
        ) {
            Button("Copy") {
                runPendingFileDrop(.copy)
            }
            .disabled(viewModel.isPerformingOperation)

            Button("Move") {
                runPendingFileDrop(.move)
            }
            .disabled(viewModel.isPerformingOperation)

            Button("Cancel", role: .cancel) {
                pendingFileDrop = nil
            }
        } message: {
            Text(pendingFileDropMessage)
        }
    }

    private var horizontalDivider: some View {
        Rectangle()
            .fill(CatppuccinMochaTheme.surface0)
            .frame(height: CatppuccinMochaTheme.hairlineBorderWidth)
    }

    private var paneSplit: some View {
        GeometryReader { geometry in
            let layout = PaneSplitLayout.resolved(
                totalWidth: geometry.size.width,
                proposedLeftWidth: leftPaneWidth
            )

            PaneSplitView(
                totalWidth: geometry.size.width,
                desiredLeftWidth: layout.leftWidth,
                dividerWidth: layout.dividerWidth
            ) {
                filePane(for: .left)
            } rightPane: {
                filePane(for: .right)
            } onCommit: { committedLeftWidth in
                let clampedLeftWidth = PaneSplitLayout.clampedLeftWidth(
                    committedLeftWidth,
                    totalWidth: geometry.size.width
                )
                leftPaneWidth = clampedLeftWidth
                updateSplitFraction(
                    totalWidth: geometry.size.width,
                    leftPaneWidth: clampedLeftWidth
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .onAppear {
                if let fraction = viewModel.splitLeftPaneFraction,
                   leftPaneWidth == nil {
                    leftPaneWidth = PaneSplitLayout.clampedLeftWidth(
                        geometry.size.width * CGFloat(fraction),
                        totalWidth: geometry.size.width
                    )
                } else {
                    leftPaneWidth = layout.leftWidth
                }
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                leftPaneWidth = PaneSplitLayout.clampedLeftWidth(
                    leftPaneWidth ?? layout.leftWidth,
                    totalWidth: newWidth
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dual-pane-split")
    }

    @ViewBuilder
    private func filePane(for side: PaneSide) -> some View {
        let pane = viewModel.pane(for: side)

        FilePaneView(
            viewModel: pane,
            isActive: viewModel.activePaneSide == side,
            paneSide: side,
            isPerformingOperation: viewModel.isPerformingOperation
        ) {
            viewModel.setActivePane(side)
        } onMoveTab: { tabID, sourceSide, destinationSide, destinationIndex in
            viewModel.moveTab(tabID: tabID, from: sourceSide, to: destinationSide, at: destinationIndex)
        } onRenameSelected: {
            prepareRenameSheet()
        } onTrashSelected: {
            prepareTrashConfirmation()
        } onDuplicateSelected: {
            Task {
                await viewModel.duplicateSelectionInActivePane()
            }
        } onDuplicate: { item in
            viewModel.setActivePane(side)
            Task {
                await viewModel.duplicateForContextMenu(clickedItem: item, in: pane)
            }
        } onCompress: { item in
            viewModel.setActivePane(side)
            Task {
                await viewModel.compressForContextMenu(clickedItem: item, in: pane)
            }
        } onCreateFolder: {
            viewModel.setActivePane(side)
            prepareNewFolderSheet()
        } onCreateFile: {
            viewModel.setActivePane(side)
            prepareNewFileSheet()
        } onPaste: {
            viewModel.setActivePane(side)
            Task {
                await viewModel.pasteIntoPane(pane)
            }
        } onStatusMessage: { message in
            viewModel.showStatusMessage(message)
        } onDropFiles: { fileURLs, sourcePaneSide, targetDirectory in
            prepareFileDrop(
                fileURLs: fileURLs,
                sourcePaneSide: sourcePaneSide,
                targetDirectory: targetDirectory,
                targetPaneSide: side
            )
        }
    }

    private func updateSplitFraction(totalWidth: CGFloat, leftPaneWidth: CGFloat) {
        guard totalWidth > 0 else {
            return
        }

        viewModel.splitLeftPaneFraction = min(max(Double(leftPaneWidth / totalWidth), 0), 1)
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                toolbarActions

                Spacer(minLength: 8)

                activePaneLabel
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    toolbarActions
                    activePaneLabel
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .foregroundStyle(CatppuccinMochaTheme.primaryText)
        .controlSize(.small)
        .padding(.horizontal, 2)
        .background(CatppuccinMochaTheme.toolbarBackground)
    }

    @ViewBuilder
    private var toolbarActions: some View {
        HStack(spacing: 8) {
            Button {
                prepareNewFolderSheet()
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .newFolder))
            .disabled(viewModel.isPerformingOperation)
            .accessibilityIdentifier("toolbar-new-folder-button")

            Button {
                prepareNewFileSheet()
            } label: {
                Label("New File", systemImage: "doc.badge.plus")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .newFile))
            .disabled(viewModel.isPerformingOperation)
            .accessibilityIdentifier("toolbar-new-file-button")

            Button {
                prepareRenameSheet()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .rename))
            .disabled(viewModel.isPerformingOperation)
            .accessibilityIdentifier("toolbar-rename-button")

            Button {
                Task {
                    await viewModel.goBackInActivePane()
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .goBack))
            .disabled(!viewModel.activePane.canGoBack)
            .accessibilityIdentifier("toolbar-back-button")

            Button {
                Task {
                    await viewModel.goForwardInActivePane()
                }
            } label: {
                Label("Forward", systemImage: "chevron.right")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .goForward))
            .disabled(!viewModel.activePane.canGoForward)
            .accessibilityIdentifier("toolbar-forward-button")

            Button {
                Task {
                    await viewModel.activePane.goUp()
                }
            } label: {
                Label("Up", systemImage: "arrow.up")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .goUp))
            .accessibilityIdentifier("toolbar-up-button")

            Button {
                Task {
                    await viewModel.activePane.refresh()
                }
            } label: {
                Label("Refresh Active", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .refreshActive))
            .accessibilityIdentifier("toolbar-refresh-active-button")

            Button {
                toggleHiddenFilesInActivePane()
            } label: {
                Label(
                    "Hidden",
                    systemImage: viewModel.activePane.includeHiddenFiles ? "eye.slash" : "eye"
                )
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .toggleHiddenFiles))

            Button {
                prepareCopyToOtherPane()
            } label: {
                Label("Copy to Other Pane", systemImage: "doc.on.doc")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .copyToOtherPane))
            .disabled(viewModel.isPerformingOperation)
            .accessibilityIdentifier("toolbar-copy-to-other-pane-button")

            Button {
                prepareMoveToOtherPane()
            } label: {
                Label("Move to Other Pane", systemImage: "arrow.right")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .moveToOtherPane))
            .disabled(viewModel.isPerformingOperation)
            .accessibilityIdentifier("toolbar-move-to-other-pane-button")

            Button {
                prepareTrashConfirmation()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(DestructiveActionButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .moveToTrash))
            .disabled(viewModel.isPerformingOperation)

            Button {
                Task {
                    await viewModel.refreshBoth()
                }
            } label: {
                Label("Refresh Both", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .refreshBoth))

            Button {
                Task {
                    await viewModel.swapPaneLocations()
                }
            } label: {
                Label("Swap Panes", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
    }

    private var activePaneLabel: some View {
        Text(viewModel.activePaneSide == .left ? "Left pane active" : "Right pane active")
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(CatppuccinMochaTheme.secondaryText)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if viewModel.isPerformingOperation {
                ProgressView()
                    .controlSize(.small)
            }

            Text(viewModel.operationStatusMessage ?? "Ready")
                .lineLimit(1)
                .foregroundStyle(viewModel.errorMessage == nil ? CatppuccinMochaTheme.secondaryText : CatppuccinMochaTheme.destructive)

            if let operationProgressText {
                Text(operationProgressText)
                    .lineLimit(1)
                    .foregroundStyle(CatppuccinMochaTheme.mutedText)
            }

            if viewModel.operationState.isRunning,
               viewModel.operationState.isCancellable {
                Button("Cancel") {
                    viewModel.cancelCurrentOperation()
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .accessibilityIdentifier("operation-cancel-button")
            }

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .background(CatppuccinMochaTheme.toolbarBackground)
    }

    private var operationProgressText: String? {
        let state = viewModel.operationState

        guard state.isRunning,
              state.totalItemCount > 0 else {
            return nil
        }

        return "\(state.completedItemCount)/\(state.totalItemCount)"
    }

    private var commandPaletteCommands: [CommandPaletteCommand] {
        let selectedItemCount = viewModel.activePane.selectedItems.count

        return [
            CommandPaletteCommand(
                id: "new-folder",
                title: "New Folder",
                systemImage: "folder.badge.plus"
            ) {
                prepareNewFolderSheet()
            },
            CommandPaletteCommand(
                id: "new-file",
                title: "New File",
                systemImage: "doc.badge.plus"
            ) {
                prepareNewFileSheet()
            },
            CommandPaletteCommand(
                id: "copy-files",
                title: "Copy Selected Files",
                systemImage: "doc.on.doc",
                disabledReason: selectedItemCount > 0 ? nil : "Select one or more items"
            ) {
                let copiedItemCount = viewModel.activePane.copySelectedItemsToPasteboard()
                if copiedItemCount > 0 {
                    viewModel.showStatusMessage(
                        copiedItemCount == 1
                            ? "Copied 1 item to the clipboard."
                            : "Copied \(copiedItemCount) items to the clipboard."
                    )
                }
            },
            CommandPaletteCommand(
                id: "paste-files",
                title: "Paste Files",
                systemImage: "doc.on.clipboard"
            ) {
                Task {
                    await viewModel.pasteIntoPane(viewModel.activePane)
                }
            },
            CommandPaletteCommand(
                id: "select-all-files",
                title: "Select All Files",
                systemImage: "checkmark.circle"
            ) {
                viewModel.activePane.selectAllVisibleItems()
            },
            CommandPaletteCommand(
                id: "duplicate-files",
                title: "Duplicate Selected Files",
                systemImage: "plus.square.on.square",
                disabledReason: selectedItemCount > 0 ? nil : "Select one or more items"
            ) {
                Task {
                    await viewModel.duplicateSelectionInActivePane()
                }
            },
            CommandPaletteCommand(
                id: "rename",
                title: "Rename",
                systemImage: "pencil",
                disabledReason: selectedItemCount == 1 ? nil : "Select exactly one item"
            ) {
                prepareRenameSheet()
            },
            CommandPaletteCommand(
                id: "copy-to-other-pane",
                title: "Copy to Other Pane",
                systemImage: "doc.on.doc",
                disabledReason: selectedItemCount > 0 ? nil : "Select one or more items"
            ) {
                prepareCopyToOtherPane()
            },
            CommandPaletteCommand(
                id: "move-to-other-pane",
                title: "Move to Other Pane",
                systemImage: "arrow.right.doc.on.clipboard",
                disabledReason: selectedItemCount > 0 ? nil : "Select one or more items"
            ) {
                prepareMoveToOtherPane()
            },
            CommandPaletteCommand(
                id: "refresh-active-pane",
                title: "Refresh Active Pane",
                systemImage: "arrow.clockwise"
            ) {
                Task {
                    await viewModel.activePane.refresh()
                }
            },
            CommandPaletteCommand(
                id: "refresh-both-panes",
                title: "Refresh Both Panes",
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                Task {
                    await viewModel.refreshBoth()
                }
            },
            CommandPaletteCommand(
                id: "toggle-hidden-files",
                title: viewModel.activePane.includeHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files",
                systemImage: "eye"
            ) {
                toggleHiddenFilesInActivePane()
            },
            CommandPaletteCommand(
                id: "go-up",
                title: "Go Up",
                systemImage: "arrow.up"
            ) {
                Task {
                    await viewModel.activePane.goUp()
                }
            },
            CommandPaletteCommand(
                id: "back",
                title: "Back",
                systemImage: "chevron.left",
                disabledReason: viewModel.activePane.canGoBack ? nil : "No back history"
            ) {
                Task {
                    await viewModel.goBackInActivePane()
                }
            },
            CommandPaletteCommand(
                id: "forward",
                title: "Forward",
                systemImage: "chevron.right",
                disabledReason: viewModel.activePane.canGoForward ? nil : "No forward history"
            ) {
                Task {
                    await viewModel.goForwardInActivePane()
                }
            },
            CommandPaletteCommand(
                id: "new-tab",
                title: "New Tab",
                systemImage: "plus.square"
            ) {
                Task {
                    await viewModel.activePane.newTab()
                }
            },
            CommandPaletteCommand(
                id: "close-tab",
                title: "Close Tab",
                systemImage: "xmark.square",
                disabledReason: viewModel.activePane.tabs.count > 1 ? nil : "Each pane needs one tab"
            ) {
                Task {
                    await viewModel.activePane.closeTab(viewModel.activePane.activeTabID)
                }
            },
            CommandPaletteCommand(
                id: "switch-active-pane",
                title: "Switch Active Pane",
                systemImage: "rectangle.2.swap"
            ) {
                switchActivePane()
            },
            CommandPaletteCommand(
                id: "show-mounted-volumes",
                title: "Show Mounted Volumes",
                systemImage: "externaldrive",
                disabledReason: "Use the Volumes section in the sidebar"
            ) {}
        ]
    }

    private func switchActivePane() {
        viewModel.setActivePane(viewModel.activePaneSide == .left ? .right : .left)
    }

    private var trashConfirmationMessage: String {
        let itemText = trashConfirmationItemCount == 1 ? "item" : "items"
        return "Move \(trashConfirmationItemCount) selected \(itemText) to Trash?"
    }

    private var pendingConflictMessage: String {
        switch pendingConflictOperation {
        case .copySelection, .moveSelection:
            return "One or more selected items already exist in the other pane. Choose how OpenPane should handle those conflicts."
        case .fileDrop(let drop, _):
            return "One or more dropped items already exist in \(drop.targetDirectory.openPaneDisplayName). Choose how OpenPane should handle those conflicts."
        case nil:
            return ""
        }
    }

    private var pendingFileDropMessage: String {
        guard let pendingFileDrop else {
            return ""
        }

        let itemText = pendingFileDrop.fileURLs.count == 1 ? "item" : "items"
        return "Choose how to place \(pendingFileDrop.fileURLs.count) \(itemText) into \(pendingFileDrop.targetDirectory.openPaneDisplayName). Move changes the original location."
    }

    private var defaultFileDropAction: DefaultFileDropAction {
        DefaultFileDropAction(rawValue: defaultFileDropActionRawValue) ?? .copy
    }

    private func prepareFileDrop(
        fileURLs: [URL],
        sourcePaneSide: PaneSide?,
        targetDirectory: URL,
        targetPaneSide: PaneSide
    ) {
        guard !viewModel.isPerformingOperation else {
            return
        }

        viewModel.setActivePane(targetPaneSide)
        let drop = PendingFileDrop(
            fileURLs: fileURLs,
            sourcePaneSide: sourcePaneSide,
            targetDirectory: targetDirectory,
            targetPaneSide: targetPaneSide
        )
        switch FileDropPreparationDecision.forOrdinaryDrop(
            defaultAction: defaultFileDropAction,
            hasPotentialConflict: hasPotentialConflict(in: drop)
        ) {
        case .ask:
            pendingFileDrop = drop
        case .resolveConflicts(let operation):
            pendingConflictOperation = .fileDrop(drop, operation)
        case .perform(let operation):
            runFileDrop(drop, operation: operation, conflictResolution: .cancel)
        }
    }

    private func runPendingFileDrop(_ operation: FileDropOperation) {
        guard let pendingFileDrop else {
            return
        }

        self.pendingFileDrop = nil
        if hasPotentialConflict(in: pendingFileDrop) {
            pendingConflictOperation = .fileDrop(pendingFileDrop, operation)
            return
        }

        runFileDrop(pendingFileDrop, operation: operation, conflictResolution: .cancel)
    }

    private func runFileDrop(
        _ pendingFileDrop: PendingFileDrop,
        operation: FileDropOperation,
        conflictResolution: FileConflictResolution
    ) {
        Task {
            switch operation {
            case .copy:
                await viewModel.copyDroppedFileURLs(
                    pendingFileDrop.fileURLs,
                    sourcePaneSide: pendingFileDrop.sourcePaneSide,
                    to: pendingFileDrop.targetDirectory,
                    in: pendingFileDrop.targetPaneSide,
                    conflictResolution: conflictResolution
                )
            case .move:
                await viewModel.moveDroppedFileURLs(
                    pendingFileDrop.fileURLs,
                    sourcePaneSide: pendingFileDrop.sourcePaneSide,
                    to: pendingFileDrop.targetDirectory,
                    in: pendingFileDrop.targetPaneSide,
                    conflictResolution: conflictResolution
                )
            }
        }
    }

    private func prepareNewFolderSheet() {
        guard !viewModel.isPerformingOperation else {
            return
        }

        newFolderName = "Untitled Folder"
        activeSheet = .newFolder
    }

    private func prepareNewFileSheet() {
        guard !viewModel.isPerformingOperation else {
            return
        }

        newFileName = "Untitled.txt"
        activeSheet = .newFile
    }

    private func toggleHiddenFilesInActivePane() {
        Task {
            await viewModel.activePane.toggleHiddenFiles()
        }
    }

    private func sheetContainer<Content: View>(
        title: String,
        subtitle: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            }

            content()
        }
        .padding(22)
        .frame(width: width)
        .background(CatppuccinMochaTheme.mantle)
        .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }

    private func themedTextField(
        _ title: String,
        text: Binding<String>,
        field: SheetField,
        onSubmit: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CatppuccinMochaTheme.mutedText)

            TextField(title, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    CatppuccinMochaTheme.surface0,
                    in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                        .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
                }
                .focused($focusedSheetField, equals: field)
                .onSubmit {
                    onSubmit?()
                }
        }
    }

    private func sheetActions(
        confirmTitle: String,
        confirmSystemImage: String,
        isConfirmDisabled: Bool,
        confirm: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Spacer()

            Button("Cancel") {
                activeSheet = nil
            }
            .buttonStyle(SecondaryActionButtonStyle())

            Button {
                confirm()
            } label: {
                Label(confirmTitle, systemImage: confirmSystemImage)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(isConfirmDisabled)
        }
    }

    private var newFolderSheet: some View {
        sheetContainer(
            title: "New Folder",
            subtitle: "Create a folder in \(viewModel.activePane.currentURL.openPaneDisplayName).",
            width: 380
        ) {
            themedTextField(
                "Folder name",
                text: $newFolderName,
                field: .newFolderName,
                onSubmit: createFolderFromSheet
            )

            sheetActions(
                confirmTitle: "Create",
                confirmSystemImage: "folder.badge.plus",
                isConfirmDisabled: viewModel.isPerformingOperation ||
                    newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                confirm: createFolderFromSheet
            )
        }
        .onAppear {
            focusedSheetField = .newFolderName
        }
    }

    private func createFolderFromSheet() {
        let folderName = newFolderName
        activeSheet = nil

        Task {
            await viewModel.createFolderInActivePane(named: folderName)
        }
    }

    private var newFileSheet: some View {
        sheetContainer(
            title: "New File",
            subtitle: "Create an empty file in \(viewModel.activePane.currentURL.openPaneDisplayName).",
            width: 380
        ) {
            themedTextField(
                "File name",
                text: $newFileName,
                field: .newFileName,
                onSubmit: createFileFromSheet
            )

            sheetActions(
                confirmTitle: "Create",
                confirmSystemImage: "doc.badge.plus",
                isConfirmDisabled: viewModel.isPerformingOperation ||
                    newFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                confirm: createFileFromSheet
            )
        }
        .onAppear {
            focusedSheetField = .newFileName
        }
    }

    private func createFileFromSheet() {
        let fileName = newFileName
        activeSheet = nil

        Task {
            await viewModel.createFileInActivePane(named: fileName)
        }
    }

    private var renameSheet: some View {
        sheetContainer(
            title: "Rename",
            subtitle: "Enter a new name for the selected item.",
            width: 380
        ) {
            themedTextField(
                "Name",
                text: $renameItemName,
                field: .renameItemName,
                onSubmit: renameFromSheet
            )

            sheetActions(
                confirmTitle: "Rename",
                confirmSystemImage: "pencil",
                isConfirmDisabled: viewModel.isPerformingOperation ||
                    renameItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                confirm: renameFromSheet
            )
        }
        .onAppear {
            focusedSheetField = .renameItemName
        }
    }

    private func prepareRenameSheet() {
        guard !viewModel.isPerformingOperation else {
            return
        }

        let selectedItems = Array(viewModel.activePane.selectedItems)

        if selectedItems.count > 1 {
            batchRenameBaseName = "Item"
            batchRenameStartingNumber = 1
            activeSheet = .batchRename
            return
        }

        guard let selectedItem = selectedItems.first else {
            Task {
                await viewModel.renameSelectedItem(to: "")
            }
            return
        }

        renameItemName = selectedItem.name
        activeSheet = .rename
    }

    private func renameFromSheet() {
        let newName = renameItemName
        activeSheet = nil

        Task {
            await viewModel.renameSelectedItem(to: newName)
        }
    }

    private var batchRenameSheet: some View {
        sheetContainer(
            title: "Batch Rename",
            subtitle: "Rename selected items with a numbered pattern.",
            width: 420
        ) {
            themedTextField(
                "Base name",
                text: $batchRenameBaseName,
                field: .batchRenameBaseName
            )

            Stepper(value: $batchRenameStartingNumber, in: 0...999_999) {
                Text("Start at \(batchRenameStartingNumber)")
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            }

            batchRenamePreview

            sheetActions(
                confirmTitle: "Rename",
                confirmSystemImage: "pencil",
                isConfirmDisabled: viewModel.isPerformingOperation ||
                    batchRenameBaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                confirm: batchRenameFromSheet
            )
        }
        .onAppear {
            focusedSheetField = .batchRenameBaseName
        }
    }

    private var batchRenamePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(CatppuccinMochaTheme.mutedText)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(batchRenamePreviewNames.prefix(5), id: \.self) { name in
                    Text(name)
                        .lineLimit(1)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(CatppuccinMochaTheme.secondaryText)
                }

                if batchRenamePreviewNames.count > 5 {
                    Text("+ \(batchRenamePreviewNames.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(CatppuccinMochaTheme.mutedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                CatppuccinMochaTheme.surface0.opacity(0.7),
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
                    .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
            }
        }
    }

    private var batchRenamePreviewNames: [String] {
        (try? FileOperationService.batchRenamePreviewNames(
            for: Array(viewModel.activePane.selectedItems),
            baseName: batchRenameBaseName,
            startingNumber: batchRenameStartingNumber,
            preserveExtensions: true
        )) ?? []
    }

    private func batchRenameFromSheet() {
        let baseName = batchRenameBaseName
        let startingNumber = batchRenameStartingNumber
        activeSheet = nil

        Task {
            await viewModel.batchRenameSelectedItems(baseName: baseName, startingNumber: startingNumber)
        }
    }

    private func prepareTrashConfirmation() {
        guard !viewModel.isPerformingOperation else {
            return
        }

        let selectedItemCount = viewModel.activePane.selectedItems.count

        guard selectedItemCount > 0 else {
            Task {
                await viewModel.trashSelectionInActivePane()
            }
            return
        }

        trashConfirmationItemCount = selectedItemCount
        isShowingTrashConfirmation = true
    }

    private func prepareCopyToOtherPane() {
        guard !viewModel.isPerformingOperation else {
            return
        }

        guard hasPotentialConflictInInactivePane else {
            Task {
                await viewModel.copySelectionToOtherPane()
            }
            return
        }

        pendingConflictOperation = .copySelection
    }

    private func prepareMoveToOtherPane() {
        guard !viewModel.isPerformingOperation else {
            return
        }

        guard hasPotentialConflictInInactivePane else {
            Task {
                await viewModel.moveSelectionToOtherPane()
            }
            return
        }

        pendingConflictOperation = .moveSelection
    }

    private func runPendingConflictOperation(with resolution: FileConflictResolution) {
        guard let pendingConflictOperation else {
            return
        }

        self.pendingConflictOperation = nil

        Task {
            switch pendingConflictOperation {
            case .copySelection:
                await viewModel.copySelectionToOtherPane(conflictResolution: resolution)
            case .moveSelection:
                await viewModel.moveSelectionToOtherPane(conflictResolution: resolution)
            case .fileDrop(let drop, let operation):
                runFileDrop(drop, operation: operation, conflictResolution: resolution)
            }
        }
    }

    private var hasPotentialConflictInInactivePane: Bool {
        let selectedItems = viewModel.activePane.selectedItems

        guard !selectedItems.isEmpty else {
            return false
        }

        return FileOperationService.hasPotentialTransferConflict(
            items: Array(selectedItems),
            to: viewModel.inactivePane.currentURL
        )
    }

    private func hasPotentialConflict(in pendingFileDrop: PendingFileDrop) -> Bool {
        FileOperationService.hasPotentialTransferConflict(
            fileURLs: pendingFileDrop.fileURLs,
            to: pendingFileDrop.targetDirectory
        )
    }
}

private struct PaneSplitView<LeftPane: View, RightPane: View>: NSViewRepresentable {
    let totalWidth: CGFloat
    let desiredLeftWidth: CGFloat
    let dividerWidth: CGFloat
    let leftPane: LeftPane
    let rightPane: RightPane
    let onCommit: (CGFloat) -> Void

    init(
        totalWidth: CGFloat,
        desiredLeftWidth: CGFloat,
        dividerWidth: CGFloat,
        @ViewBuilder leftPane: () -> LeftPane,
        @ViewBuilder rightPane: () -> RightPane,
        onCommit: @escaping (CGFloat) -> Void
    ) {
        self.totalWidth = totalWidth
        self.desiredLeftWidth = desiredLeftWidth
        self.dividerWidth = dividerWidth
        self.leftPane = leftPane()
        self.rightPane = rightPane()
        self.onCommit = onCommit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommit: onCommit)
    }

    func makeNSView(context: Context) -> PaneSplitContainerView<LeftPane, RightPane> {
        let containerView = PaneSplitContainerView(leftPane: leftPane, rightPane: rightPane)
        containerView.onCommit = { [weak coordinator = context.coordinator] leftWidth in
            coordinator?.commit(leftWidth)
        }
        return containerView
    }

    func updateNSView(_ containerView: PaneSplitContainerView<LeftPane, RightPane>, context: Context) {
        context.coordinator.onCommit = onCommit
        containerView.onCommit = { [weak coordinator = context.coordinator] leftWidth in
            coordinator?.commit(leftWidth)
        }
        containerView.update(
            leftPane: leftPane,
            rightPane: rightPane,
            totalWidth: totalWidth,
            desiredLeftWidth: desiredLeftWidth,
            dividerWidth: dividerWidth
        )
    }

    final class Coordinator: NSObject {
        fileprivate var onCommit: (CGFloat) -> Void

        init(onCommit: @escaping (CGFloat) -> Void) {
            self.onCommit = onCommit
        }

        func commit(_ leftWidth: CGFloat) {
            onCommit(leftWidth)
        }
    }
}

private final class PaneSplitContainerView<LeftPane: View, RightPane: View>: NSView, PaneSplitDividerViewDelegate {
    fileprivate var onCommit: (CGFloat) -> Void = { _ in }

    private let leftHostingView: NSHostingView<LeftPane>
    private let rightHostingView: NSHostingView<RightPane>
    private let dividerView = PaneSplitDividerView()
    private let previewView = PaneSplitDividerPreviewView()
    private var totalWidth: CGFloat = 0
    private var dividerWidth: CGFloat = PaneSplitLayout.defaultDividerWidth
    private var committedLeftWidth: CGFloat = 0
    private var dragStartLeftWidth: CGFloat?
    private var previewLeftWidth: CGFloat?

    init(leftPane: LeftPane, rightPane: RightPane) {
        self.leftHostingView = NSHostingView(rootView: leftPane)
        self.rightHostingView = NSHostingView(rootView: rightPane)
        super.init(frame: .zero)

        wantsLayer = true
        postsFrameChangedNotifications = true

        dividerView.delegate = self
        previewView.isHidden = true

        addSubview(leftHostingView)
        addSubview(rightHostingView)
        addSubview(dividerView)
        addSubview(previewView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    func update(
        leftPane: LeftPane,
        rightPane: RightPane,
        totalWidth: CGFloat,
        desiredLeftWidth: CGFloat,
        dividerWidth: CGFloat
    ) {
        leftHostingView.rootView = leftPane
        rightHostingView.rootView = rightPane
        self.totalWidth = totalWidth
        self.dividerWidth = dividerWidth
        dividerView.preferredWidth = dividerWidth
        previewView.preferredWidth = dividerWidth

        guard dragStartLeftWidth == nil else {
            return
        }

        applyCommittedLeftWidth(desiredLeftWidth)
    }

    override func layout() {
        super.layout()

        guard dragStartLeftWidth == nil else {
            layoutPanes(leftWidth: committedLeftWidth)
            layoutPreview()
            return
        }

        let clampedLeftWidth = clampedLeftWidth(committedLeftWidth)
        committedLeftWidth = clampedLeftWidth
        layoutPanes(leftWidth: clampedLeftWidth)
    }

    func dividerDidBeginDragging(_ dividerView: PaneSplitDividerView) {
        dragStartLeftWidth = committedLeftWidth
        previewLeftWidth = committedLeftWidth
        previewView.isHidden = false
        layoutPreview()
    }

    func divider(_ dividerView: PaneSplitDividerView, didDragBy deltaX: CGFloat) {
        let startLeftWidth = dragStartLeftWidth ?? committedLeftWidth
        previewLeftWidth = clampedLeftWidth(startLeftWidth + deltaX)
        layoutPreview()
    }

    func dividerDidEndDragging(_ dividerView: PaneSplitDividerView) {
        let finalLeftWidth = previewLeftWidth ?? committedLeftWidth
        dragStartLeftWidth = nil
        previewLeftWidth = nil
        previewView.isHidden = true
        applyCommittedLeftWidth(finalLeftWidth)
        onCommit(committedLeftWidth)
    }

    private func applyCommittedLeftWidth(_ proposedLeftWidth: CGFloat) {
        let clampedLeftWidth = clampedLeftWidth(proposedLeftWidth)
        guard abs(committedLeftWidth - clampedLeftWidth) > 0.5 else {
            layoutPanes(leftWidth: clampedLeftWidth)
            return
        }

        committedLeftWidth = clampedLeftWidth
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func layoutPanes(leftWidth: CGFloat) {
        let safeTotalWidth = resolvedTotalWidth
        let safeDividerWidth = resolvedDividerWidth(for: safeTotalWidth)
        let safeLeftWidth = PaneSplitLayout.clampedLeftWidth(
            leftWidth,
            totalWidth: safeTotalWidth,
            dividerWidth: safeDividerWidth
        )
        let rightWidth = max(0, safeTotalWidth - safeDividerWidth - safeLeftWidth)

        leftHostingView.frame = NSRect(x: 0, y: 0, width: safeLeftWidth, height: bounds.height)
        dividerView.frame = NSRect(x: safeLeftWidth, y: 0, width: safeDividerWidth, height: bounds.height)
        rightHostingView.frame = NSRect(
            x: safeLeftWidth + safeDividerWidth,
            y: 0,
            width: rightWidth,
            height: bounds.height
        )
    }

    private func layoutPreview() {
        guard let previewLeftWidth else {
            return
        }

        let safeTotalWidth = resolvedTotalWidth
        let safeDividerWidth = resolvedDividerWidth(for: safeTotalWidth)
        previewView.frame = NSRect(
            x: clampedLeftWidth(previewLeftWidth),
            y: 0,
            width: safeDividerWidth,
            height: bounds.height
        )
        previewView.needsDisplay = true
    }

    private func clampedLeftWidth(_ proposedLeftWidth: CGFloat) -> CGFloat {
        PaneSplitLayout.clampedLeftWidth(
            proposedLeftWidth,
            totalWidth: resolvedTotalWidth,
            dividerWidth: resolvedDividerWidth(for: resolvedTotalWidth)
        )
    }

    private var resolvedTotalWidth: CGFloat {
        bounds.width > 0 ? bounds.width : totalWidth
    }

    private func resolvedDividerWidth(for totalWidth: CGFloat) -> CGFloat {
        min(max(0, dividerWidth), max(0, totalWidth))
    }
}

private protocol PaneSplitDividerViewDelegate: AnyObject {
    func dividerDidBeginDragging(_ dividerView: PaneSplitDividerView)
    func divider(_ dividerView: PaneSplitDividerView, didDragBy deltaX: CGFloat)
    func dividerDidEndDragging(_ dividerView: PaneSplitDividerView)
}

private final class PaneSplitDividerView: NSView {
    weak var delegate: PaneSplitDividerViewDelegate?
    var preferredWidth: CGFloat = PaneSplitLayout.defaultDividerWidth {
        didSet {
            needsDisplay = true
        }
    }
    private var dragStartLocationInWindow: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds.insetBy(dx: -4, dy: 0), cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocationInWindow = event.locationInWindow
        delegate?.dividerDidBeginDragging(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartLocationInWindow else {
            return
        }

        delegate?.divider(self, didDragBy: event.locationInWindow.x - dragStartLocationInWindow.x)
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.dividerDidEndDragging(self)
        dragStartLocationInWindow = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        PaneSplitDividerColors.idleDivider.setFill()
        bounds.fill()

        let lineWidth = max(1, CatppuccinMochaTheme.hairlineBorderWidth)
        let lineRect = NSRect(
            x: bounds.midX - lineWidth / 2,
            y: bounds.minY + 12,
            width: lineWidth,
            height: max(0, bounds.height - 24)
        )
        PaneSplitDividerColors.previewDivider.setFill()
        NSBezierPath(roundedRect: lineRect, xRadius: lineWidth / 2, yRadius: lineWidth / 2).fill()
    }

    private func commonInit() {
        wantsLayer = true
        toolTip = "Drag to resize panes"
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityIdentifier("pane-split-divider")
        setAccessibilityLabel("Pane split divider")
    }
}

private final class PaneSplitDividerPreviewView: NSView {
    var preferredWidth: CGFloat = PaneSplitLayout.defaultDividerWidth {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        PaneSplitDividerColors.activeDivider.setFill()
        bounds.fill()

        let lineWidth = max(2, min(preferredWidth, 3))
        let lineRect = NSRect(
            x: bounds.midX - lineWidth / 2,
            y: bounds.minY + 8,
            width: lineWidth,
            height: max(0, bounds.height - 16)
        )
        PaneSplitDividerColors.previewDivider.setFill()
        NSBezierPath(roundedRect: lineRect, xRadius: lineWidth / 2, yRadius: lineWidth / 2).fill()
    }
}

private enum PaneSplitDividerColors {
    static let idleDivider = NSColor(
        srgbRed: 0x45 / 255,
        green: 0x47 / 255,
        blue: 0x5a / 255,
        alpha: 0.95
    )
    static let activeDivider = NSColor(
        srgbRed: 0x89 / 255,
        green: 0xb4 / 255,
        blue: 0xfa / 255,
        alpha: 0.38
    )
    static let previewDivider = NSColor(
        srgbRed: 0x89 / 255,
        green: 0xb4 / 255,
        blue: 0xfa / 255,
        alpha: 0.88
    )
}
