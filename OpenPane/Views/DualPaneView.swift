//
//  DualPaneView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct DualPaneView: View {
    @ObservedObject var viewModel: DualPaneViewModel

    @State private var isShowingNewFolderSheet = false
    @State private var newFolderName = "Untitled Folder"

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
        .sheet(isPresented: $isShowingNewFolderSheet) {
            newFolderSheet
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                newFolderName = "Untitled Folder"
                isShowingNewFolderSheet = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }

            Button {
                Task {
                    await viewModel.copySelectionToOtherPane()
                }
            } label: {
                Label("Copy to Other Pane", systemImage: "doc.on.doc")
            }

            Button {
                Task {
                    await viewModel.moveSelectionToOtherPane()
                }
            } label: {
                Label("Move to Other Pane", systemImage: "folder.badge.arrow.right")
            }

            Button {
                Task {
                    await viewModel.refreshBoth()
                }
            } label: {
                Label("Refresh Both", systemImage: "arrow.clockwise")
            }

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
                    isShowingNewFolderSheet = false
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
        isShowingNewFolderSheet = false

        Task {
            await viewModel.createFolderInActivePane(named: folderName)
        }
    }
}
