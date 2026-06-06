//
//  FilePaneView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct FilePaneView: View {
    @ObservedObject var viewModel: FilePaneViewModel
    var isActive: Bool = false
    var onActivate: () -> Void = {}

    private let fileIconService = FileIconService.shared

    private var selectedItemIDs: Binding<Set<FileItem.ID>> {
        Binding {
            Set(viewModel.selectedItems.map(\.id))
        } set: { newSelection in
            viewModel.selectedItems = Set(viewModel.filteredItems.filter { newSelection.contains($0.id) })
        }
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
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                onActivate()
            }
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(height: 3)
        }
        .overlay {
            Rectangle()
                .stroke(isActive ? Color.accentColor.opacity(0.7) : Color.gray.opacity(0.25), lineWidth: isActive ? 2 : 1)
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
                Task {
                    await viewModel.openSelectedItem()
                }
            } label: {
                Label("Open", systemImage: "arrow.forward")
            }
            .disabled(viewModel.selectedItems.count != 1)

            Button {
                viewModel.revealSelectedItemsInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }
            .disabled(viewModel.selectedItems.isEmpty)

            TextField("Filter", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            PathBarView(path: viewModel.currentURL.path)
        }
    }

    private var fileTable: some View {
        Table(viewModel.filteredItems, selection: selectedItemIDs) {
            TableColumn("Name") { item in
                HStack(spacing: 6) {
                    Image(nsImage: fileIconService.icon(for: item))
                        .resizable()
                        .frame(width: 16, height: 16)

                    Text(item.displayName)
                        .lineLimit(1)
                }
                    .onTapGesture(count: 2) {
                        Task {
                            await viewModel.open(item)
                        }
                    }
                    .contextMenu {
                        Button("Open") {
                            Task {
                                await viewModel.open(item)
                            }
                        }

                        Button("Reveal in Finder") {
                            viewModel.selectedItems = [item]
                            viewModel.revealSelectedItemsInFinder()
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
