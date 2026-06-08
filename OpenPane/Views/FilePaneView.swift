//
//  FilePaneView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import AppKit
import SwiftUI

private enum FilePaneListMetrics {
    static let contentPadding: CGFloat = 6
    static let rowHorizontalPadding: CGFloat = 8
    static let headerHorizontalPadding = contentPadding + rowHorizontalPadding
    static let columnSpacing: CGFloat = 18
    static let sizeColumnWidth: CGFloat = 92
    static let modifiedColumnWidth: CGFloat = 150
    static let kindColumnWidth: CGFloat = 128
}

struct FilePaneView: View {
    @ObservedObject var viewModel: FilePaneViewModel
    @EnvironmentObject private var keyboardShortcutStore: KeyboardShortcutStore
    var isActive: Bool = false
    var paneSide: PaneSide?
    var onActivate: () -> Void = {}
    var onMoveTab: (FilePaneTab.ID, PaneSide, PaneSide) -> Void = { _, _, _ in }
    var onRenameSelected: () -> Void = {}
    var onTrashSelected: () -> Void = {}
    var onDuplicate: (FileItem) -> Void = { _ in }
    var onCompress: (FileItem) -> Void = { _ in }
    var onCreateFolder: () -> Void = {}
    var onCreateFile: () -> Void = {}
    var onPaste: () -> Void = {}
    var onStatusMessage: (String) -> Void = { _ in }

    @State private var isTabDropTargeted = false
    @State private var activeSortColumn: FileListColumn?
    @State private var isSortAscending = true
    @State private var infoItem: FileItem?

    private let fileIconService = FileIconService.shared

    private enum FileListColumn: String {
        case name = "Name"
        case size = "Size"
        case modified = "Modified"
        case kind = "Kind"
    }

    private enum PaneContentState {
        case loading
        case error(String)
        case emptyFolder
        case emptySearch
        case emptyRecursiveSearch
    }

    private var paneSurfaceColor: Color {
        isActive ? CatppuccinMochaTheme.paneBackgroundElevated : CatppuccinMochaTheme.windowBackground
    }

    private var selectedCountText: String {
        let count = viewModel.selectedItems.count
        return count == 1 ? "1 selected" : "\(count) selected"
    }

    private var paneContentState: PaneContentState? {
        if viewModel.isLoading {
            return .loading
        }

        if let errorMessage = viewModel.errorMessage,
           viewModel.filteredItems.isEmpty {
            return .error(errorMessage)
        }

        guard viewModel.filteredItems.isEmpty else {
            return nil
        }

        if viewModel.isShowingRecursiveSearchResults {
            return .emptyRecursiveSearch
        }

        if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .emptySearch
        }

        return .emptyFolder
    }

    private var shouldShowErrorBanner: Bool {
        viewModel.errorMessage != nil &&
            !viewModel.filteredItems.isEmpty &&
            !viewModel.isLoading
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

            if shouldShowErrorBanner, let errorMessage = viewModel.errorMessage {
                paneErrorBanner(errorMessage)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            ZStack {
                fileTable

                if let paneContentState {
                    paneStateView(paneContentState)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CatppuccinMochaTheme.base)
            .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(paneSurfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge))
        .shadow(
            color: isActive ? CatppuccinMochaTheme.accent.opacity(0.12) : CatppuccinMochaTheme.crust.opacity(0.65),
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
        .sheet(item: $infoItem) { item in
            FileInfoView(
                item: item,
                onCopyPath: {
                    viewModel.copyPath(of: item)
                    onStatusMessage("Copied path.")
                },
                onRevealInFinder: {
                    viewModel.selectedItems = [item]
                    viewModel.revealSelectedItemsInFinder()
                },
                onClose: {
                    infoItem = nil
                }
            )
        }
    }

    private func paneErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(CatppuccinMochaTheme.destructive)

            Text(message)
                .lineLimit(2)
                .foregroundStyle(CatppuccinMochaTheme.primaryText)

            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            CatppuccinMochaTheme.destructive.opacity(0.12),
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
                .stroke(CatppuccinMochaTheme.destructive.opacity(0.28), lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }

    private func paneStateView(_ state: PaneContentState) -> some View {
        let details = paneStateDetails(for: state)

        return VStack(spacing: 12) {
            if case .loading = state {
                ProgressView()
                    .controlSize(.small)
                    .tint(CatppuccinMochaTheme.accent)
            } else {
                Image(systemName: details.systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(details.tint)
                    .frame(width: 42, height: 42)
                    .background(details.tint.opacity(0.12), in: Circle())
            }

            VStack(spacing: 5) {
                Text(details.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)

                Text(details.message)
                    .font(.system(size: 12))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: 320)
        .background(
            CatppuccinMochaTheme.mantle.opacity(0.96),
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
        .allowsHitTesting(false)
    }

    private func paneStateDetails(for state: PaneContentState) -> (systemImage: String, title: String, message: String, tint: Color) {
        switch state {
        case .loading:
            return (
                "arrow.clockwise",
                "Loading folder",
                "Reading \(viewModel.currentURL.openPaneDisplayName)...",
                CatppuccinMochaTheme.accent
            )
        case .error(let message):
            return (
                "exclamationmark.triangle",
                "Couldn’t load this folder",
                message,
                CatppuccinMochaTheme.destructive
            )
        case .emptyFolder:
            return (
                "folder",
                "Folder is empty",
                "There are no visible items in \(viewModel.currentURL.openPaneDisplayName).",
                CatppuccinMochaTheme.accentSecondary
            )
        case .emptySearch:
            return (
                "magnifyingglass",
                "No matches",
                "No items in this folder match your filter.",
                CatppuccinMochaTheme.mutedText
            )
        case .emptyRecursiveSearch:
            return (
                "magnifyingglass",
                "No recursive results",
                "No files or folders under this location match your search.",
                CatppuccinMochaTheme.mutedText
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
            .buttonStyle(ToolbarIconButtonStyle())

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
            .buttonStyle(PaneTabButtonStyle(isActive: tab.id == viewModel.activeTabID))

            Button {
                Task {
                    await viewModel.closeTab(tab.id)
                }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(PaneTabCloseButtonStyle())
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
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .preview))
            .disabled(viewModel.selectedItems.count != 1)

            Button {
                viewModel.revealSelectedItemsInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .disabled(viewModel.selectedItems.isEmpty)

            searchField

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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CatppuccinMochaTheme.mutedText)

            TextField("Filter", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)
        }
        .padding(.horizontal, 9)
        .frame(width: 180, height: 28)
        .background(
            CatppuccinMochaTheme.surface0.opacity(0.78),
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                .stroke(CatppuccinMochaTheme.surface1.opacity(0.76), lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
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
                            isPaneActive: isActive,
                            onSelect: {
                                selectItem(item)
                            },
                            onContextSelect: {
                                selectItemForContextMenu(item)
                            },
                            onOpen: {
                                Task {
                                    await viewModel.open(item)
                                }
                            },
                            applicationOptions: viewModel.applicationsAvailableToOpen(item),
                            onOpenWithApplication: { applicationURL in
                                viewModel.open(item, withApplication: applicationURL)
                            },
                            onChooseApplication: {
                                viewModel.chooseApplicationToOpen(item)
                            },
                            onShare: {
                                viewModel.shareForContextMenu(clickedItem: item)
                            },
                            onCopyItems: {
                                let copiedItemCount = viewModel.copyItemsForContextMenu(clickedItem: item)
                                onStatusMessage(copyItemsStatusMessage(itemCount: copiedItemCount))
                            },
                            onGetInfo: {
                                infoItem = item
                            },
                            onRename: onRenameSelected,
                            onTrash: onTrashSelected,
                            onDuplicate: {
                                onDuplicate(item)
                            },
                            onCompress: {
                                onCompress(item)
                            },
                            onReveal: {
                                viewModel.selectedItems = [item]
                                viewModel.revealSelectedItemsInFinder()
                            },
                            onPreview: {
                                viewModel.selectedItems = [item]
                                viewModel.previewSelectedItem()
                            },
                            onCopyText: { format in
                                let copiedItemCount = viewModel.copyTextForContextMenu(clickedItem: item, format: format)
                                onStatusMessage(copyStatusMessage(for: format, itemCount: copiedItemCount))
                            },
                            compressItemCount: viewModel.contextMenuTargetItems(clickedItem: item).count
                        )
                    }
                }
                .padding(FilePaneListMetrics.contentPadding)
            }
            .background(CatppuccinMochaTheme.base)
            .contextMenu {
                EmptyPaneContextMenu(
                    includeHiddenFiles: viewModel.includeHiddenFiles,
                    canPasteFiles: viewModel.hasFileURLsToPaste(),
                    onNewFolder: onCreateFolder,
                    onNewFile: onCreateFile,
                    onPaste: onPaste,
                    onRefresh: {
                        Task {
                            await viewModel.refresh()
                        }
                    },
                    onToggleHiddenFiles: {
                        Task {
                            await viewModel.toggleHiddenFiles()
                        }
                    }
                )
            }
            .onRightClickInside {
                onActivate()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CatppuccinMochaTheme.base)
    }

    private var fileListHeader: some View {
        HStack(spacing: FilePaneListMetrics.columnSpacing) {
            sortHeader(.name)
                .frame(maxWidth: .infinity, alignment: .leading)

            sortHeader(.size)
                .frame(width: FilePaneListMetrics.sizeColumnWidth, alignment: .trailing)

            sortHeader(.modified)
                .frame(width: FilePaneListMetrics.modifiedColumnWidth, alignment: .leading)

            sortHeader(.kind)
                .frame(width: FilePaneListMetrics.kindColumnWidth, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(CatppuccinMochaTheme.mutedText)
        .padding(.horizontal, FilePaneListMetrics.headerHorizontalPadding)
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
            sortHeaderLabel(column)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sortHeaderLabel(_ column: FileListColumn) -> some View {
        HStack(spacing: 4) {
            if column == .size {
                sortIndicator(for: column)
            }

            Text(column.rawValue)
                .lineLimit(1)

            if column != .size {
                sortIndicator(for: column)
            }
        }
        .frame(maxWidth: .infinity, alignment: column == .size ? .trailing : .leading)
    }

    @ViewBuilder
    private func sortIndicator(for column: FileListColumn) -> some View {
        if activeSortColumn == column {
            Image(systemName: isSortAscending ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CatppuccinMochaTheme.accentSecondary)
        }
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

    private func selectItemForContextMenu(_ item: FileItem) {
        onActivate()
        viewModel.selectForContextMenu(item)
    }

    private func copyStatusMessage(for format: FileItemCopyTextFormat, itemCount: Int) -> String {
        let suffix = itemCount == 1 ? "" : "s"

        switch format {
        case .absolutePath:
            return "Copied path\(suffix)."
        case .fileURL:
            return "Copied file URL\(suffix)."
        case .name:
            return "Copied name\(suffix)."
        }
    }

    private func copyItemsStatusMessage(itemCount: Int) -> String {
        let suffix = itemCount == 1 ? "" : "s"
        return "Copied \(itemCount) item\(suffix)."
    }
}

private struct FilePaneRowView: View {
    let item: FileItem
    let icon: NSImage
    let isSelected: Bool
    let isPaneActive: Bool
    let onSelect: () -> Void
    let onContextSelect: () -> Void
    let onOpen: () -> Void
    let applicationOptions: [ApplicationOption]
    let onOpenWithApplication: (URL) -> Void
    let onChooseApplication: () -> Void
    let onShare: () -> Void
    let onCopyItems: () -> Void
    let onGetInfo: () -> Void
    let onRename: () -> Void
    let onTrash: () -> Void
    let onDuplicate: () -> Void
    let onCompress: () -> Void
    let onReveal: () -> Void
    let onPreview: () -> Void
    let onCopyText: (FileItemCopyTextFormat) -> Void
    let compressItemCount: Int

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
        HStack(spacing: FilePaneListMetrics.columnSpacing) {
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
                .frame(width: FilePaneListMetrics.sizeColumnWidth, alignment: .trailing)

            Text(item.formattedModifiedDate)
                .frame(width: FilePaneListMetrics.modifiedColumnWidth, alignment: .leading)

            Text(item.kindDescription)
                .frame(width: FilePaneListMetrics.kindColumnWidth, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundStyle(CatppuccinMochaTheme.subtext0)
        .padding(.horizontal, FilePaneListMetrics.rowHorizontalPadding)
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
        .onRightClickInside {
            onContextSelect()
        }
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onSelect()
            onOpen()
        }
        .contextMenu {
            FileItemContextMenu(
                item: item,
                isPaneActive: isPaneActive,
                onPrepare: onContextSelect,
                onOpen: onOpen,
                applicationOptions: applicationOptions,
                onOpenWithApplication: onOpenWithApplication,
                onChooseApplication: onChooseApplication,
                onShare: onShare,
                onCopyItems: onCopyItems,
                onGetInfo: onGetInfo,
                onRename: onRename,
                onTrash: onTrash,
                onDuplicate: onDuplicate,
                onCompress: onCompress,
                onPreview: onPreview,
                onReveal: onReveal,
                onCopyText: onCopyText,
                compressItemCount: compressItemCount
            )
        }
    }
}

private struct FileItemContextMenu: View {
    let item: FileItem
    let isPaneActive: Bool
    let onPrepare: () -> Void
    let onOpen: () -> Void
    let applicationOptions: [ApplicationOption]
    let onOpenWithApplication: (URL) -> Void
    let onChooseApplication: () -> Void
    let onShare: () -> Void
    let onCopyItems: () -> Void
    let onGetInfo: () -> Void
    let onRename: () -> Void
    let onTrash: () -> Void
    let onDuplicate: () -> Void
    let onCompress: () -> Void
    let onPreview: () -> Void
    let onReveal: () -> Void
    let onCopyText: (FileItemCopyTextFormat) -> Void
    let compressItemCount: Int

    var body: some View {
        Button {
            onPrepare()
            onOpen()
        } label: {
            Label("Open", systemImage: "arrow.forward")
        }

        Menu {
            Button {
                onPrepare()
                onOpen()
            } label: {
                Label("Default App", systemImage: "app")
            }

            if !applicationOptions.isEmpty {
                Divider()

                ForEach(applicationOptions) { application in
                    Button {
                        onPrepare()
                        onOpenWithApplication(application.url)
                    } label: {
                        ApplicationOptionLabel(application: application)
                    }
                }
            }

            Divider()

            Button {
                onPrepare()
                onChooseApplication()
            } label: {
                Label("Choose Application...", systemImage: "ellipsis.circle")
            }
        } label: {
            Label("Open With", systemImage: "square.and.arrow.up")
        }

        Button {
            onPrepare()
            onShare()
        } label: {
            Label("Share...", systemImage: "square.and.arrow.up")
        }

        Button {
            onPrepare()
            onCopyItems()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
            onPrepare()
            onGetInfo()
        } label: {
            Label("Get Info", systemImage: "info.circle")
        }

        Divider()

        Button {
            onPrepare()
            onRename()
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            onPrepare()
            onDuplicate()
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Button {
            onPrepare()
            onCompress()
        } label: {
            Label(compressTitle, systemImage: "archivebox")
        }

        Button(role: .destructive) {
            onPrepare()
            onTrash()
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }

        Divider()

        Button {
            onPrepare()
            onPreview()
        } label: {
            Label("Quick Look", systemImage: "eye")
        }
        .disabled(item.isDirectory)

        Button {
            onPrepare()
            onReveal()
        } label: {
            Label("Reveal in Finder", systemImage: "finder")
        }

        Menu {
            Button {
                onPrepare()
                onCopyText(.absolutePath)
            } label: {
                Label("Copy Absolute Path", systemImage: "doc.on.clipboard")
            }

            Button {
                onPrepare()
                onCopyText(.fileURL)
            } label: {
                Label("Copy File URL", systemImage: "link")
            }

            Button {
                onPrepare()
                onCopyText(.name)
            } label: {
                Label("Copy Name", systemImage: "textformat")
            }
        } label: {
            Label("Copy Path", systemImage: "doc.on.clipboard")
        }

        if !isPaneActive {
            Divider()

            Label("Activates this pane", systemImage: "sidebar.leading")
        }
    }

    private var compressTitle: String {
        if compressItemCount > 1 {
            return "Compress \(compressItemCount) Items"
        }

        return "Compress \"\(item.displayName)\""
    }
}

private struct ApplicationOptionLabel: View {
    let application: ApplicationOption

    var body: some View {
        if let icon = application.icon {
            Label {
                Text(application.name)
            } icon: {
                Image(nsImage: icon)
            }
        } else {
            Label(application.name, systemImage: "app")
        }
    }
}

private struct EmptyPaneContextMenu: View {
    let includeHiddenFiles: Bool
    let canPasteFiles: Bool
    let onNewFolder: () -> Void
    let onNewFile: () -> Void
    let onPaste: () -> Void
    let onRefresh: () -> Void
    let onToggleHiddenFiles: () -> Void

    var body: some View {
        Button {
            onNewFolder()
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }

        Button {
            onNewFile()
        } label: {
            Label("New File", systemImage: "doc.badge.plus")
        }

        Button {
            onPaste()
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        .disabled(!canPasteFiles)

        Divider()

        Button {
            onRefresh()
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }

        Button {
            onToggleHiddenFiles()
        } label: {
            Label(
                includeHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files",
                systemImage: includeHiddenFiles ? "eye.slash" : "eye"
            )
        }
    }
}

private struct RightClickMonitorView: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> RightClickMonitorNSView {
        let view = RightClickMonitorNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: RightClickMonitorNSView, context: Context) {
        nsView.action = action
    }

    static func dismantleNSView(_ nsView: RightClickMonitorNSView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

private final class RightClickMonitorNSView: NSView {
    var action: () -> Void = {}
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        stopMonitoring()

        guard window != nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self,
                  event.window === self.window else {
                return event
            }

            let location = self.convert(event.locationInWindow, from: nil)

            if self.bounds.contains(location) {
                self.action()
            }

            return event
        }
    }

    func stopMonitoring() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    deinit {
        stopMonitoring()
    }
}

private extension View {
    func onRightClickInside(_ action: @escaping () -> Void) -> some View {
        background(RightClickMonitorView(action: action))
    }
}
