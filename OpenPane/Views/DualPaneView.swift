//
//  DualPaneView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct DualPaneView: View {
    @ObservedObject var viewModel: DualPaneViewModel
    @EnvironmentObject private var keyboardShortcutStore: KeyboardShortcutStore

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
        VStack(spacing: 0) {
            toolbar
                .padding(12)

            horizontalDivider

            HSplitView {
                FilePaneView(
                    viewModel: viewModel.leftPane,
                    isActive: viewModel.activePaneSide == .left,
                    paneSide: .left
                ) {
                    viewModel.setActivePane(.left)
                } onMoveTab: { tabID, sourceSide, destinationSide, destinationIndex in
                    viewModel.moveTab(tabID: tabID, from: sourceSide, to: destinationSide, at: destinationIndex)
                } onRenameSelected: {
                    prepareRenameSheet()
                } onTrashSelected: {
                    prepareTrashConfirmation()
                } onDuplicate: { item in
                    viewModel.setActivePane(.left)
                    Task {
                        await viewModel.duplicateForContextMenu(clickedItem: item, in: viewModel.leftPane)
                    }
                } onCompress: { item in
                    viewModel.setActivePane(.left)
                    Task {
                        await viewModel.compressForContextMenu(clickedItem: item, in: viewModel.leftPane)
                    }
                } onCreateFolder: {
                    viewModel.setActivePane(.left)
                    prepareNewFolderSheet()
                } onCreateFile: {
                    viewModel.setActivePane(.left)
                    prepareNewFileSheet()
                } onPaste: {
                    viewModel.setActivePane(.left)
                    Task {
                        await viewModel.pasteIntoPane(viewModel.leftPane)
                    }
                } onStatusMessage: { message in
                    viewModel.showStatusMessage(message)
                } onDropFiles: { fileURLs, sourcePaneSide, targetDirectory in
                    prepareFileDrop(
                        fileURLs: fileURLs,
                        sourcePaneSide: sourcePaneSide,
                        targetDirectory: targetDirectory,
                        targetPaneSide: .left
                    )
                }
                .frame(minWidth: 320)

                FilePaneView(
                    viewModel: viewModel.rightPane,
                    isActive: viewModel.activePaneSide == .right,
                    paneSide: .right
                ) {
                    viewModel.setActivePane(.right)
                } onMoveTab: { tabID, sourceSide, destinationSide, destinationIndex in
                    viewModel.moveTab(tabID: tabID, from: sourceSide, to: destinationSide, at: destinationIndex)
                } onRenameSelected: {
                    prepareRenameSheet()
                } onTrashSelected: {
                    prepareTrashConfirmation()
                } onDuplicate: { item in
                    viewModel.setActivePane(.right)
                    Task {
                        await viewModel.duplicateForContextMenu(clickedItem: item, in: viewModel.rightPane)
                    }
                } onCompress: { item in
                    viewModel.setActivePane(.right)
                    Task {
                        await viewModel.compressForContextMenu(clickedItem: item, in: viewModel.rightPane)
                    }
                } onCreateFolder: {
                    viewModel.setActivePane(.right)
                    prepareNewFolderSheet()
                } onCreateFile: {
                    viewModel.setActivePane(.right)
                    prepareNewFileSheet()
                } onPaste: {
                    viewModel.setActivePane(.right)
                    Task {
                        await viewModel.pasteIntoPane(viewModel.rightPane)
                    }
                } onStatusMessage: { message in
                    viewModel.showStatusMessage(message)
                } onDropFiles: { fileURLs, sourcePaneSide, targetDirectory in
                    prepareFileDrop(
                        fileURLs: fileURLs,
                        sourcePaneSide: sourcePaneSide,
                        targetDirectory: targetDirectory,
                        targetPaneSide: .right
                    )
                }
                .frame(minWidth: 320)
            }
            .padding(12)
            .background(CatppuccinMochaTheme.appBackground)

            horizontalDivider

            statusBar
        }
        .background(CatppuccinMochaTheme.windowBackground)
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
            Button("Copy Here") {
                runPendingFileDrop(.copy)
            }
            .disabled(viewModel.isPerformingOperation)

            Button("Move Here") {
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

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                prepareNewFolderSheet()
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .newFolder))
            .disabled(viewModel.isPerformingOperation)

            Button {
                prepareRenameSheet()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .rename))
            .disabled(viewModel.isPerformingOperation)

            Button {
                Task {
                    await viewModel.activePane.goUp()
                }
            } label: {
                Label("Up", systemImage: "arrow.up")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .goUp))

            Button {
                Task {
                    await viewModel.activePane.refresh()
                }
            } label: {
                Label("Refresh Active", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .refreshActive))

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

            Button {
                prepareMoveToOtherPane()
            } label: {
                Label("Move to Other Pane", systemImage: "arrow.right")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .moveToOtherPane))
            .disabled(viewModel.isPerformingOperation)

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

            Spacer()

            Text(viewModel.activePaneSide == .left ? "Left pane active" : "Right pane active")
                .foregroundStyle(CatppuccinMochaTheme.secondaryText)
        }
        .foregroundStyle(CatppuccinMochaTheme.primaryText)
        .controlSize(.small)
        .padding(.horizontal, 2)
        .background(CatppuccinMochaTheme.toolbarBackground)
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

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .background(CatppuccinMochaTheme.toolbarBackground)
    }

    private var trashConfirmationMessage: String {
        let itemText = trashConfirmationItemCount == 1 ? "item" : "items"
        return "Move \(trashConfirmationItemCount) selected \(itemText) to Trash?"
    }

    private var pendingFileDropMessage: String {
        guard let pendingFileDrop else {
            return ""
        }

        let itemText = pendingFileDrop.fileURLs.count == 1 ? "item" : "items"
        return "Choose how to place \(pendingFileDrop.fileURLs.count) \(itemText) into \(pendingFileDrop.targetDirectory.openPaneDisplayName). Move changes the original location."
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
        pendingFileDrop = PendingFileDrop(
            fileURLs: fileURLs,
            sourcePaneSide: sourcePaneSide,
            targetDirectory: targetDirectory,
            targetPaneSide: targetPaneSide
        )
        let itemText = fileURLs.count == 1 ? "item" : "items"
        viewModel.showStatusMessage("Ready to drop \(fileURLs.count) \(itemText) into \(targetDirectory.openPaneDisplayName).")
    }

    private func runPendingFileDrop(_ operation: FileDropOperation) {
        guard let pendingFileDrop else {
            return
        }

        self.pendingFileDrop = nil
        viewModel.setActivePane(pendingFileDrop.targetPaneSide)

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

        let inactivePaneNames = Set(viewModel.inactivePane.items.map(\.name))
        return selectedItems.contains { inactivePaneNames.contains($0.name) }
    }

    private func hasPotentialConflict(in pendingFileDrop: PendingFileDrop) -> Bool {
        pendingFileDrop.fileURLs.contains { fileURL in
            let destinationURL = pendingFileDrop.targetDirectory.appendingPathComponent(fileURL.lastPathComponent)
            return FileManager.default.fileExists(atPath: destinationURL.path)
        }
    }
}
