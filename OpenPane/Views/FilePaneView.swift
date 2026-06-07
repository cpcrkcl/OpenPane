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
    var paneSide: PaneSide?
    var onActivate: () -> Void = {}
    var onMoveTab: (FilePaneTab.ID, PaneSide, PaneSide) -> Void = { _, _, _ in }

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
            tabBar
                .padding(.horizontal, 8)
                .padding(.top, 8)

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

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(viewModel.tabs) { tab in
                tabHeader(for: tab)
            }

            Button {
                Task {
                    await viewModel.newTab()
                }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()
        }
        .dropDestination(for: FilePaneTabDragItem.self) { items, _ in
            guard let paneSide,
                  let item = items.first,
                  item.sourcePaneSide != paneSide else {
                return false
            }

            onMoveTab(item.tabID, item.sourcePaneSide, paneSide)
            return true
        }
    }

    @ViewBuilder
    private func tabHeader(for tab: FilePaneTab) -> some View {
        let header = HStack(spacing: 4) {
            Button {
                Task {
                    await viewModel.switchToTab(tab.id)
                }
            } label: {
                Text(tab.title)
                    .lineLimit(1)
                    .frame(maxWidth: 140)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(tab.id == viewModel.activeTabID ? .accentColor : nil)

            Button {
                Task {
                    await viewModel.closeTab(tab.id)
                }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .disabled(viewModel.tabs.count == 1)
        }
        .padding(.trailing, 2)

        if let paneSide {
            header.draggable(FilePaneTabDragItem(tabID: tab.id, sourcePaneSide: paneSide))
        } else {
            header
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
                    if viewModel.isShowingRecursiveSearchResults {
                        await viewModel.performRecursiveSearch()
                    } else {
                        await viewModel.refresh()
                    }
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
                viewModel.previewSelectedItem()
            } label: {
                Label("Preview", systemImage: "eye")
            }
            .keyboardShortcut(.space, modifiers: [])
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

            Button {
                Task {
                    await viewModel.performRecursiveSearch()
                }
            } label: {
                Label("Recursive Search", systemImage: "magnifyingglass")
            }
            .disabled(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if viewModel.isShowingRecursiveSearchResults {
                Button {
                    viewModel.clearRecursiveSearch()
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
            }

            PathBarView(path: viewModel.currentURL.path)
        }
    }

    private var fileTable: some View {
        Table(viewModel.filteredItems, selection: selectedItemIDs, sortOrder: $viewModel.sortOrder) {
            TableColumn("Name", value: \.name) { item in
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

                        Button("Preview") {
                            viewModel.selectedItems = [item]
                            viewModel.previewSelectedItem()
                        }
                    }
            }

            TableColumn("Size", value: \.sortSize) { item in
                Text(item.formattedSize)
                    .foregroundStyle(.secondary)
            }

            TableColumn("Modified", value: \.sortModifiedDate) { item in
                Text(item.formattedModifiedDate)
                    .foregroundStyle(.secondary)
            }

            TableColumn("Kind", value: \.kindDescription) { item in
                Text(item.kindDescription)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
