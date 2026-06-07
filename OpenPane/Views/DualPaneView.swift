//
//  DualPaneView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct DualPaneView: View {
    @ObservedObject var viewModel: DualPaneViewModel

    @State private var newFolderName = "Untitled Folder"
    @State private var renameItemName = ""
    @State private var batchRenameBaseName = "Item"
    @State private var batchRenameStartingNumber = 1
    @State private var activeSheet: ActiveSheet?
    @State private var isShowingTrashConfirmation = false
    @State private var trashConfirmationItemCount = 0
    @State private var pendingConflictOperation: PendingConflictOperation?

    private enum ActiveSheet: Identifiable {
        case newFolder
        case rename
        case batchRename

        var id: String {
            switch self {
            case .newFolder:
                "newFolder"
            case .rename:
                "rename"
            case .batchRename:
                "batchRename"
            }
        }
    }

    private enum PendingConflictOperation {
        case copy
        case move
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(12)

            Divider()

            HSplitView {
                FilePaneView(
                    viewModel: viewModel.leftPane,
                    isActive: viewModel.activePaneSide == .left,
                    paneSide: .left
                ) {
                    viewModel.setActivePane(.left)
                } onMoveTab: { tabID, sourceSide, destinationSide in
                    viewModel.moveTab(tabID, from: sourceSide, to: destinationSide)
                }
                .frame(minWidth: 320)

                FilePaneView(
                    viewModel: viewModel.rightPane,
                    isActive: viewModel.activePaneSide == .right,
                    paneSide: .right
                ) {
                    viewModel.setActivePane(.right)
                } onMoveTab: { tabID, sourceSide, destinationSide in
                    viewModel.moveTab(tabID, from: sourceSide, to: destinationSide)
                }
                .frame(minWidth: 320)
            }
            .padding(10)
            .background(CatppuccinMochaTheme.appBackground)

            Divider()

            statusBar
        }
        .background(CatppuccinMochaTheme.windowBackground)
        .alert(
            "File Operation Error",
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

            Button("Replace", role: .destructive) {
                runPendingConflictOperation(with: .replace)
            }

            Button("Skip") {
                runPendingConflictOperation(with: .skip)
            }

            Button("Cancel", role: .cancel) {
                pendingConflictOperation = nil
            }
        } message: {
            Text("One or more selected items already exist in the other pane.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                prepareNewFolderSheet()
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(viewModel.isPerformingOperation)

            Button {
                prepareRenameSheet()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(viewModel.isPerformingOperation)

            Button {
                Task {
                    await viewModel.activePane.goUp()
                }
            } label: {
                Label("Up", systemImage: "arrow.up")
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button {
                Task {
                    await viewModel.activePane.refresh()
                }
            } label: {
                Label("Refresh Active", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)

            Button {
                prepareCopyToOtherPane()
            } label: {
                Label("Copy to Other Pane", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(viewModel.isPerformingOperation)

            Button {
                prepareMoveToOtherPane()
            } label: {
                Label("Move to Other Pane", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(viewModel.isPerformingOperation)

            Button {
                prepareTrashConfirmation()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.isPerformingOperation)

            Button {
                Task {
                    await viewModel.refreshBoth()
                }
            } label: {
                Label("Refresh Both", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button {
                Task {
                    await viewModel.swapPaneLocations()
                }
            } label: {
                Label("Swap Panes", systemImage: "arrow.left.arrow.right")
            }

            Spacer()

            Text(viewModel.activePaneSide == .left ? "Left pane active" : "Right pane active")
                .foregroundStyle(CatppuccinMochaTheme.secondaryText)
        }
        .foregroundStyle(CatppuccinMochaTheme.primaryText)
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
                .foregroundColor(viewModel.errorMessage == nil ? CatppuccinMochaTheme.secondaryText : CatppuccinMochaTheme.destructive)

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

    private func prepareNewFolderSheet() {
        guard !viewModel.isPerformingOperation else {
            return
        }

        newFolderName = "Untitled Folder"
        activeSheet = .newFolder
    }

    private var newFolderSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Folder")
                .font(.headline)

            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createFolderFromSheet)

            HStack {
                Spacer()

                Button("Cancel") {
                    activeSheet = nil
                }

                Button("Create") {
                    createFolderFromSheet()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    viewModel.isPerformingOperation ||
                        newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func createFolderFromSheet() {
        let folderName = newFolderName
        activeSheet = nil

        Task {
            await viewModel.createFolderInActivePane(named: folderName)
        }
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename")
                .font(.headline)

            TextField("Name", text: $renameItemName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(renameFromSheet)

            HStack {
                Spacer()

                Button("Cancel") {
                    activeSheet = nil
                }

                Button("Rename") {
                    renameFromSheet()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    viewModel.isPerformingOperation ||
                        renameItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(20)
        .frame(width: 360)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Batch Rename")
                .font(.headline)

            TextField("Base name", text: $batchRenameBaseName)
                .textFieldStyle(.roundedBorder)

            Stepper(value: $batchRenameStartingNumber, in: 0...999_999) {
                Text("Start at \(batchRenameStartingNumber)")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.subheadline)
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)

                ForEach(batchRenamePreviewNames.prefix(5), id: \.self) { name in
                    Text(name)
                        .lineLimit(1)
                        .font(.caption)
                }

                if batchRenamePreviewNames.count > 5 {
                    Text("+ \(batchRenamePreviewNames.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(CatppuccinMochaTheme.mutedText)
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    activeSheet = nil
                }

                Button("Rename") {
                    batchRenameFromSheet()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    viewModel.isPerformingOperation ||
                        batchRenameBaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(20)
        .frame(width: 380)
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

        pendingConflictOperation = .copy
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

        pendingConflictOperation = .move
    }

    private func runPendingConflictOperation(with resolution: FileConflictResolution) {
        guard let pendingConflictOperation else {
            return
        }

        self.pendingConflictOperation = nil

        Task {
            switch pendingConflictOperation {
            case .copy:
                await viewModel.copySelectionToOtherPane(conflictResolution: resolution)
            case .move:
                await viewModel.moveSelectionToOtherPane(conflictResolution: resolution)
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
}
