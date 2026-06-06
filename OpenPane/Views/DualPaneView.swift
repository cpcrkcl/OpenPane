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
    @State private var activeSheet: ActiveSheet?
    @State private var isShowingTrashConfirmation = false
    @State private var trashConfirmationItemCount = 0

    private enum ActiveSheet: Identifiable {
        case newFolder
        case rename

        var id: String {
            switch self {
            case .newFolder:
                "newFolder"
            case .rename:
                "rename"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(12)

            Divider()

            HSplitView {
                FilePaneView(
                    viewModel: viewModel.leftPane,
                    isActive: viewModel.activePaneSide == .left
                ) {
                    viewModel.setActivePane(.left)
                }
                .frame(minWidth: 320)

                FilePaneView(
                    viewModel: viewModel.rightPane,
                    isActive: viewModel.activePaneSide == .right
                ) {
                    viewModel.setActivePane(.right)
                }
                .frame(minWidth: 320)
            }
        }
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

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(trashConfirmationMessage)
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

            Button {
                prepareRenameSheet()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .keyboardShortcut(.return, modifiers: [])

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
                Task {
                    await viewModel.copySelectionToOtherPane()
                }
            } label: {
                Label("Copy to Other Pane", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Button {
                Task {
                    await viewModel.moveSelectionToOtherPane()
                }
            } label: {
                Label("Move to Other Pane", systemImage: "folder.badge.arrow.right")
            }
            .keyboardShortcut("m", modifiers: [.command, .option])

            Button {
                prepareTrashConfirmation()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)

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
                .foregroundStyle(.secondary)
        }
    }

    private var trashConfirmationMessage: String {
        let itemText = trashConfirmationItemCount == 1 ? "item" : "items"
        return "Move \(trashConfirmationItemCount) selected \(itemText) to Trash?"
    }

    private func prepareNewFolderSheet() {
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
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                .disabled(renameItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func prepareRenameSheet() {
        let selectedItems = Array(viewModel.activePane.selectedItems)

        guard selectedItems.count == 1, let selectedItem = selectedItems.first else {
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

    private func prepareTrashConfirmation() {
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
}
