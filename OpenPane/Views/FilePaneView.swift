//
//  FilePaneView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct FilePaneView: View {
    @ObservedObject var viewModel: FilePaneViewModel

    private var selectedItemIDs: Binding<Set<FileItem.ID>> {
        Binding {
            Set(viewModel.selectedItems.map(\.id))
        } set: { newSelection in
            viewModel.selectedItems = Set(viewModel.items.filter { newSelection.contains($0.id) })
        }
    }

    private var primarySelectedItem: FileItem? {
        viewModel.selectedItems.first
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(12)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            ZStack {
                fileTable

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
        .task {
            await viewModel.loadCurrentDirectory()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await viewModel.goUp()
                }
            } label: {
                Label("Up", systemImage: "arrow.up")
            }

            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Button {
                viewModel.includeHiddenFiles.toggle()
                Task {
                    await viewModel.refresh()
                }
            } label: {
                Label(
                    viewModel.includeHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files",
                    systemImage: viewModel.includeHiddenFiles ? "eye.slash" : "eye"
                )
            }

            Button {
                guard let primarySelectedItem else {
                    return
                }

                Task {
                    await viewModel.open(primarySelectedItem)
                }
            } label: {
                Label("Open", systemImage: "arrow.forward")
            }
            .disabled(viewModel.selectedItems.count != 1)

            PathBarView(path: viewModel.currentURL.path)
        }
    }

    private var fileTable: some View {
        Table(viewModel.items, selection: selectedItemIDs) {
            TableColumn("Name") { item in
                Label(item.displayName, systemImage: item.isDirectory ? "folder" : "doc")
                    .onTapGesture(count: 2) {
                        Task {
                            await viewModel.open(item)
                        }
                    }
            }

            TableColumn("Size") { item in
                Text(item.formattedSize)
                    .foregroundStyle(.secondary)
            }

            TableColumn("Modified") { item in
                Text(item.formattedModifiedDate)
                    .foregroundStyle(.secondary)
            }

            TableColumn("Kind") { item in
                Text(item.kindDescription)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
