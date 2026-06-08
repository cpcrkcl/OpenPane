//
//  FilePaneView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import AppKit
import SwiftUI

struct FilePaneView: View {
    @ObservedObject var viewModel: FilePaneViewModel
    var isActive: Bool = false
    var paneSide: PaneSide?
    var onActivate: () -> Void = {}
    var onMoveTab: (FilePaneTab.ID, PaneSide, PaneSide) -> Void = { _, _, _ in }

    @State private var isTabDropTargeted = false
    @State private var activeSortColumn: FileListColumn?
    @State private var isSortAscending = true

    private let fileIconService = FileIconService.shared

    private enum FileListColumn: String {
        case name = "Name"
        case size = "Size"
        case modified = "Modified"
        case kind = "Kind"
    }

    private var paneSurfaceColor: Color {
        isActive ? CatppuccinMochaTheme.paneBackgroundElevated : CatppuccinMochaTheme.windowBackground
    }

    private var selectedCountText: String {
        let count = viewModel.selectedItems.count
        return count == 1 ? "1 selected" : "\(count) selected"
    }

    var body: some View {
        VStack(spacing: 8) {
            tabBar
                .padding(.horizontal, 10)
                .padding(.top, 10)

            paneHeader
                .padding(.horizontal, 12)

            toolbar
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(CatppuccinMochaTheme.destructive)
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
            .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(paneSurfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge))
        .shadow(
            color: isActive ? CatppuccinMochaTheme.accent.opacity(0.12) : Color.black.opacity(0.18),
            radius: isActive ? 12 : 6,
            x: 0,
            y: isActive ? 5 : 2
        )
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
                .fill(isActive ? CatppuccinMochaTheme.accentSecondary : Color.clear)
                .frame(height: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                .stroke(
                    isActive ? CatppuccinMochaTheme.activePaneBorder.opacity(0.95) : CatppuccinMochaTheme.inactivePaneBorder.opacity(0.55),
                    lineWidth: isActive ? CatppuccinMochaTheme.paneBorderWidth : CatppuccinMochaTheme.hairlineBorderWidth
                )
        }
    }

    private var paneHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(viewModel.currentURL.openPaneDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CatppuccinMochaTheme.primaryText)
                        .lineLimit(1)

                    if !viewModel.selectedItems.isEmpty {
                        Text(selectedCountText)
                            .font(.caption)
                            .foregroundStyle(CatppuccinMochaTheme.accentSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                CatppuccinMochaTheme.accentSecondary.opacity(0.12),
                                in: Capsule()
                            )
                    }
                }

                PathBarView(path: viewModel.currentURL.path)
            }

            Spacer(minLength: 0)
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
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .background(isTabDropTargeted ? CatppuccinMochaTheme.accent.opacity(0.14) : Color.clear)
        .onDrop(
            of: [FilePaneTabDragItem.typeIdentifier],
            isTargeted: $isTabDropTargeted,
            perform: handleTabDrop(_:)
        )
    }

    private func handleTabDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let destinationSide = paneSide,
              let provider = providers.first(where: {
                  $0.hasItemConformingToTypeIdentifier(FilePaneTabDragItem.typeIdentifier)
              }) else {
            return false
        }

        let moveTab = onMoveTab

        provider.loadDataRepresentation(forTypeIdentifier: FilePaneTabDragItem.typeIdentifier) { data, _ in
            guard let data,
                  let item = FilePaneTabDragItem.decoded(from: data),
                  item.sourcePaneSide != destinationSide else {
                return
            }

            Task { @MainActor in
                moveTab(item.tabID, item.sourcePaneSide, destinationSide)
            }
        }

        return true
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
            .tint(tab.id == viewModel.activeTabID ? CatppuccinMochaTheme.accent : nil)

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
            header.onDrag {
                tabDragProvider(for: tab, paneSide: paneSide)
            }
        } else {
            header
        }
    }

    private func tabDragProvider(for tab: FilePaneTab, paneSide: PaneSide) -> NSItemProvider {
        let provider = NSItemProvider()
        let item = FilePaneTabDragItem(tabID: tab.id, sourcePaneSide: paneSide)

        if let data = item.encodedData {
            provider.registerDataRepresentation(
                forTypeIdentifier: FilePaneTabDragItem.typeIdentifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
        }

        return provider
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
            .buttonStyle(ToolbarIconButtonStyle())

            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ToolbarIconButtonStyle())

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
            .buttonStyle(SecondaryActionButtonStyle())

            Button {
                Task {
                    await viewModel.openSelectedItem()
                }
            } label: {
                Label("Open", systemImage: "arrow.forward")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .disabled(viewModel.selectedItems.count != 1)

            Button {
                viewModel.previewSelectedItem()
            } label: {
                Label("Preview", systemImage: "eye")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .keyboardShortcut(.space, modifiers: [])
            .disabled(viewModel.selectedItems.count != 1)

            Button {
                viewModel.revealSelectedItemsInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }
            .buttonStyle(SecondaryActionButtonStyle())
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
            .buttonStyle(SecondaryActionButtonStyle())
            .disabled(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if viewModel.isShowingRecursiveSearchResults {
                Button {
                    viewModel.clearRecursiveSearch()
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
        }
        .controlSize(.small)
        .foregroundStyle(CatppuccinMochaTheme.primaryText)
    }

    private var fileTable: some View {
        VStack(spacing: 0) {
            fileListHeader

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.filteredItems) { item in
                        FilePaneRowView(
                            item: item,
                            icon: fileIconService.icon(for: item),
                            isSelected: viewModel.selectedItems.contains(item),
                            onSelect: {
                                selectItem(item)
                            },
                            onOpen: {
                                Task {
                                    await viewModel.open(item)
                                }
                            },
                            onReveal: {
                                viewModel.selectedItems = [item]
                                viewModel.revealSelectedItemsInFinder()
                            },
                            onPreview: {
                                viewModel.selectedItems = [item]
                                viewModel.previewSelectedItem()
                            }
                        )
                    }
                }
                .padding(6)
            }
            .background(CatppuccinMochaTheme.base)
        }
        .background(CatppuccinMochaTheme.base)
    }

    private var fileListHeader: some View {
        HStack(spacing: 0) {
            sortHeader(.name)
                .frame(maxWidth: .infinity, alignment: .leading)

            sortHeader(.size)
                .frame(width: 92, alignment: .trailing)

            sortHeader(.modified)
                .frame(width: 150, alignment: .leading)

            sortHeader(.kind)
                .frame(width: 128, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(CatppuccinMochaTheme.mutedText)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(CatppuccinMochaTheme.mantle)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CatppuccinMochaTheme.surface0)
                .frame(height: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }

    private func sortHeader(_ column: FileListColumn) -> some View {
        Button {
            applySort(column)
        } label: {
            HStack(spacing: 4) {
                Text(column.rawValue)
                    .lineLimit(1)

                if activeSortColumn == column {
                    Image(systemName: isSortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CatppuccinMochaTheme.accentSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: column == .size ? .trailing : .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func applySort(_ column: FileListColumn) {
        if activeSortColumn == column {
            isSortAscending.toggle()
        } else {
            activeSortColumn = column
            isSortAscending = true
        }

        let order: SortOrder = isSortAscending ? .forward : .reverse

        switch column {
        case .name:
            viewModel.sortOrder = [KeyPathComparator(\.name, order: order)]
        case .size:
            viewModel.sortOrder = [KeyPathComparator(\.sortSize, order: order)]
        case .modified:
            viewModel.sortOrder = [KeyPathComparator(\.sortModifiedDate, order: order)]
        case .kind:
            viewModel.sortOrder = [KeyPathComparator(\.kindDescription, order: order)]
        }
    }

    private func selectItem(_ item: FileItem) {
        if NSEvent.modifierFlags.contains(.command) {
            if viewModel.selectedItems.contains(item) {
                viewModel.selectedItems.remove(item)
            } else {
                viewModel.selectedItems.insert(item)
            }
        } else {
            viewModel.selectedItems = [item]
        }
    }
}

private struct FilePaneRowView: View {
    let item: FileItem
    let icon: NSImage
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onPreview: () -> Void

    @State private var isHovered = false

    private var rowBackground: Color {
        if isSelected {
            return CatppuccinMochaTheme.rowSelectedBackground
        }

        if isHovered {
            return CatppuccinMochaTheme.rowHoverBackground
        }

        return Color.clear
    }

    private var rowBorder: Color {
        isSelected ? CatppuccinMochaTheme.accent.opacity(0.45) : Color.clear
    }

    private var nameColor: Color {
        item.isDirectory ? CatppuccinMochaTheme.lavender : CatppuccinMochaTheme.primaryText
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 17, height: 17)
                    .opacity(item.isDirectory ? 1 : 0.92)

                Text(item.displayName)
                    .font(.system(size: 13, weight: item.isDirectory ? .medium : .regular))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.formattedSize)
                .frame(width: 92, alignment: .trailing)

            Text(item.formattedModifiedDate)
                .frame(width: 150, alignment: .leading)

            Text(item.kindDescription)
                .frame(width: 128, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundStyle(CatppuccinMochaTheme.subtext0)
        .padding(.horizontal, 8)
        .frame(minHeight: 31)
        .background(
            rowBackground,
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                .stroke(rowBorder, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onSelect()
            onOpen()
        }
        .contextMenu {
            Button("Open") {
                onOpen()
            }

            Button("Reveal in Finder") {
                onReveal()
            }

            Button("Preview") {
                onPreview()
            }
        }
    }
}
