//
//  FilePaneView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum FilePaneListMetrics {
    static let contentPadding: CGFloat = 6
    static let rowHorizontalPadding: CGFloat = 8
    static let headerHorizontalPadding = contentPadding + rowHorizontalPadding
    static let columnSpacing: CGFloat = 18
    static let sizeColumnWidth: CGFloat = 92
    static let modifiedColumnWidth: CGFloat = 150
    static let kindColumnWidth: CGFloat = 128
}

private let fileURLPasteboardTypeIdentifier = NSPasteboard.PasteboardType.fileURL.rawValue
private let fileNamesPasteboardTypeIdentifier = NSPasteboard.PasteboardType("NSFilenamesPboardType").rawValue
private let externalFileDropTypeIdentifiers = [
    UTType.fileURL.identifier,
    fileURLPasteboardTypeIdentifier,
    UTType.url.identifier,
    fileNamesPasteboardTypeIdentifier
]
private let fileDropTypeIdentifiers = [
    FileDragPayload.typeIdentifier,
    UTType.fileURL.identifier,
    fileURLPasteboardTypeIdentifier,
    UTType.url.identifier,
    fileNamesPasteboardTypeIdentifier
].uniqued()

private struct FileDrop {
    let sourcePaneSide: PaneSide?
    let fileURLs: [URL]
}

private enum FileDropVisualState {
    case none
    case valid
    case invalid
}

struct FilePaneView: View {
    @ObservedObject var viewModel: FilePaneViewModel
    @EnvironmentObject private var keyboardShortcutStore: KeyboardShortcutStore
    var isActive: Bool = false
    var paneSide: PaneSide?
    var isPerformingOperation = false
    var onActivate: () -> Void = {}
    var onMoveTab: (FilePaneTab.ID, PaneSide, PaneSide, Int?) -> Void = { _, _, _, _ in }
    var onRenameSelected: () -> Void = {}
    var onTrashSelected: () -> Void = {}
    var onDuplicate: (FileItem) -> Void = { _ in }
    var onCompress: (FileItem) -> Void = { _ in }
    var onCreateFolder: () -> Void = {}
    var onCreateFile: () -> Void = {}
    var onPaste: () -> Void = {}
    var onStatusMessage: (String) -> Void = { _ in }
    var onDropFiles: ([URL], PaneSide?, URL) -> Void = { _, _, _ in }

    @State private var isTabAppendDropTargeted = false
    @State private var targetedTabID: FilePaneTab.ID?
    @State private var isPaneFileDropTargeted = false
    @State private var targetedFolderDropID: FileItem.ID?
    @State private var infoItem: FileItem?
    @State private var isShowingViewOptions = false

    private let fileIconService = FileIconService.shared

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

    private var isAnyTabDropTargeted: Bool {
        isTabAppendDropTargeted || targetedTabID != nil
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
            .overlay {
                if isPerformingOperation {
                    operationInProgressOverlay
                }
            }
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
        .sheet(isPresented: $isShowingViewOptions) {
            FilePaneViewOptionsView(
                viewModel: viewModel,
                onClose: {
                    isShowingViewOptions = false
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

    private var operationInProgressOverlay: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(CatppuccinMochaTheme.accent)

            Text("Operation in progress")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CatppuccinMochaTheme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            CatppuccinMochaTheme.surface0.opacity(0.88),
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
                .stroke(CatppuccinMochaTheme.surface2.opacity(0.7), lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
        .shadow(color: CatppuccinMochaTheme.crust.opacity(0.45), radius: 10, y: 4)
        .allowsHitTesting(false)
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

            tabAppendDropTarget
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .padding(3)
        .background(
            isAnyTabDropTargeted
                ? CatppuccinMochaTheme.surface1.opacity(0.5)
                : CatppuccinMochaTheme.surface0.opacity(0.26),
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
                .stroke(
                    isAnyTabDropTargeted
                        ? CatppuccinMochaTheme.accent.opacity(0.42)
                        : CatppuccinMochaTheme.surface1.opacity(0.55),
                    lineWidth: CatppuccinMochaTheme.hairlineBorderWidth
                )
        )
    }

    private var tabAppendDropTarget: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Rectangle())
            .background(
                isTabAppendDropTargeted
                    ? CatppuccinMochaTheme.surface2.opacity(0.32)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
            )
            .overlay(alignment: .leading) {
                if isTabAppendDropTargeted {
                    Capsule()
                        .fill(CatppuccinMochaTheme.accentSecondary)
                        .frame(width: 3, height: 22)
                        .padding(.leading, 4)
                }
            }
            .onDrop(
                of: [FilePaneTabDragItem.typeIdentifier],
                isTargeted: $isTabAppendDropTargeted,
                perform: { providers in
                    handleTabDrop(providers, destinationIndex: viewModel.tabs.count)
                }
            )
    }

    private func handleTabDrop(_ providers: [NSItemProvider], destinationIndex: Int?) -> Bool {
        guard let destinationSide = paneSide,
              let provider = providers.first(where: {
                  $0.hasItemConformingToTypeIdentifier(FilePaneTabDragItem.typeIdentifier)
              }) else {
            return false
        }

        let moveTab = onMoveTab

        provider.loadDataRepresentation(forTypeIdentifier: FilePaneTabDragItem.typeIdentifier) { data, _ in
            guard let data,
                  let item = FilePaneTabDragItem.decoded(from: data) else {
                return
            }

            Task { @MainActor in
                targetedTabID = nil
                isTabAppendDropTargeted = false
                moveTab(item.tabID, item.sourcePaneSide, destinationSide, destinationIndex)
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
        .padding(2)
        .background(
            targetedTabID == tab.id
                ? CatppuccinMochaTheme.surface2.opacity(0.36)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
        )
        .overlay(alignment: .leading) {
            if targetedTabID == tab.id {
                Capsule()
                    .fill(CatppuccinMochaTheme.accent)
                    .frame(width: 3, height: 22)
                    .padding(.leading, 1)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                .stroke(
                    targetedTabID == tab.id
                        ? CatppuccinMochaTheme.accent.opacity(0.62)
                        : Color.clear,
                    lineWidth: CatppuccinMochaTheme.hairlineBorderWidth
                )
        )

        if let paneSide {
            header.onDrag {
                tabDragProvider(for: tab, paneSide: paneSide)
            } preview: {
                tabDragPreview(for: tab)
            }
            .onDrop(
                of: [FilePaneTabDragItem.typeIdentifier],
                isTargeted: tabDropTargetBinding(for: tab.id),
                perform: { providers in
                    handleTabDrop(providers, destinationIndex: tabIndex(for: tab.id))
                }
            )
        } else {
            header
        }
    }

    private func tabDragPreview(for tab: FilePaneTab) -> some View {
        Text(tab.title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(CatppuccinMochaTheme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                CatppuccinMochaTheme.surface2.opacity(0.95),
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                    .stroke(CatppuccinMochaTheme.accent.opacity(0.72), lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
            )
            .shadow(color: CatppuccinMochaTheme.accent.opacity(0.18), radius: 8, x: 0, y: 3)
    }

    private func tabDropTargetBinding(for tabID: FilePaneTab.ID) -> Binding<Bool> {
        Binding {
            targetedTabID == tabID
        } set: { isTargeted in
            if isTargeted {
                targetedTabID = tabID
            } else if targetedTabID == tabID {
                targetedTabID = nil
            }
        }
    }

    private func tabIndex(for tabID: FilePaneTab.ID) -> Int? {
        viewModel.tabs.firstIndex { $0.id == tabID }
    }

    private func tabDragProvider(for tab: FilePaneTab, paneSide: PaneSide) -> NSItemProvider {
        let provider = NSItemProvider()
        let item = FilePaneTabDragItem(
            tabID: tab.id,
            sourcePaneSide: paneSide,
            currentURL: tab.currentURL
        )

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
                            paneSide: paneSide,
                            isOperationInProgress: isPerformingOperation,
                            onSelect: {
                                selectItem(item)
                            },
                            onDragItems: {
                                onActivate()
                                return viewModel.itemsForDrag(startingFrom: item)
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
                                viewModel.revealForContextMenu(clickedItem: item)
                            },
                            onPreview: {
                                viewModel.selectedItems = [item]
                                viewModel.previewSelectedItem()
                            },
                            onCopyText: { format in
                                let copiedItemCount = viewModel.copyTextForContextMenu(clickedItem: item, format: format)
                                onStatusMessage(copyStatusMessage(for: format, itemCount: copiedItemCount))
                            },
                            onDropFiles: { providers, targetDirectory in
                                handleFileDrop(providers, targetDirectory: targetDirectory)
                            },
                            onFileDropTargetedChange: { isTargeted in
                                if isTargeted {
                                    targetedFolderDropID = item.id
                                } else if targetedFolderDropID == item.id {
                                    targetedFolderDropID = nil
                                }
                            },
                            compressItemCount: viewModel.contextMenuTargetItems(clickedItem: item).count
                        )
                    }
                }
                .padding(FilePaneListMetrics.contentPadding)
            }
            .background(CatppuccinMochaTheme.base)
            .overlay {
                if isPaneFileDropTargeted && targetedFolderDropID == nil {
                    paneDropTargetOverlay
                }
            }
            .onDrop(
                of: fileDropTypeIdentifiers,
                isTargeted: $isPaneFileDropTargeted,
                perform: { providers in
                    handleFileDrop(providers, targetDirectory: viewModel.currentURL)
                }
            )
            .contextMenu {
                EmptyPaneContextMenu(
                    includeHiddenFiles: viewModel.includeHiddenFiles,
                    canPasteFiles: viewModel.hasFileURLsToPaste(),
                    onNewFolder: onCreateFolder,
                    onNewFile: onCreateFile,
                    onPaste: onPaste,
                    onShowViewOptions: {
                        isShowingViewOptions = true
                    },
                    onCopyCurrentFolderPath: {
                        viewModel.copyCurrentFolderPath()
                        onStatusMessage("Copied current folder path.")
                    },
                    onRevealCurrentFolder: {
                        viewModel.revealCurrentFolderInFinder()
                    },
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

            sortHeader(.modifiedDate)
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

    private var paneDropTargetOverlay: some View {
        RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
            .stroke(CatppuccinMochaTheme.accent.opacity(0.68), lineWidth: CatppuccinMochaTheme.paneBorderWidth)
            .background(
                CatppuccinMochaTheme.accent.opacity(0.08),
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
            )
            .overlay(alignment: .center) {
                dropHint(
                    title: "Drop to copy here",
                    subtitle: "Move available after drop",
                    systemImage: "doc.on.doc",
                    tint: CatppuccinMochaTheme.accent
                )
            }
            .padding(3)
            .allowsHitTesting(false)
    }

    private func dropHint(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)

                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CatppuccinMochaTheme.mutedText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            CatppuccinMochaTheme.surface0.opacity(0.92),
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
                .stroke(tint.opacity(0.38), lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
        .shadow(color: CatppuccinMochaTheme.crust.opacity(0.4), radius: 10, y: 4)
    }

    private func sortHeader(_ option: FileSortOption) -> some View {
        Button {
            applySort(option)
        } label: {
            sortHeaderLabel(option)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sortHeaderLabel(_ option: FileSortOption) -> some View {
        HStack(spacing: 4) {
            if option == .size {
                sortIndicator(for: option)
            }

            Text(option.columnTitle)
                .lineLimit(1)

            if option != .size {
                sortIndicator(for: option)
            }
        }
        .frame(maxWidth: .infinity, alignment: option == .size ? .trailing : .leading)
    }

    @ViewBuilder
    private func sortIndicator(for option: FileSortOption) -> some View {
        if viewModel.sortOption == option {
            Image(systemName: viewModel.sortDirection == .ascending ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CatppuccinMochaTheme.accentSecondary)
        }
    }

    private func applySort(_ option: FileSortOption) {
        if viewModel.sortOption == option {
            viewModel.sortDirection = viewModel.sortDirection == .ascending ? .descending : .ascending
        } else {
            viewModel.sortOption = option
            viewModel.sortDirection = .ascending
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

    private func handleFileDrop(_ providers: [NSItemProvider], targetDirectory: URL) -> Bool {
        guard providers.contains(where: canLoadFileDropProvider) else {
            return false
        }

        targetedFolderDropID = nil
        isPaneFileDropTargeted = false

        loadDroppedFiles(from: providers) { drop in
            Task { @MainActor in
                let uniqueURLs = uniqueFileURLs(drop.fileURLs)
                let itemDescription = itemCountDescription(uniqueURLs.count)
                let targetName = targetDirectory.openPaneDisplayName

                if uniqueURLs.isEmpty {
                    onStatusMessage("No file URLs found to drop.")
                } else {
                    onStatusMessage("Ready to drop \(itemDescription) into \(targetName).")
                    onDropFiles(uniqueURLs, drop.sourcePaneSide, targetDirectory)
                }
            }
        }

        return true
    }

    private func canLoadFileDropProvider(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(FileDragPayload.typeIdentifier) ||
            externalFileTypeIdentifier(for: provider) != nil
    }

    private func externalFileTypeIdentifier(for provider: NSItemProvider) -> String? {
        externalFileDropTypeIdentifiers.first {
            provider.hasItemConformingToTypeIdentifier($0)
        }
    }

    private func loadDroppedFiles(from providers: [NSItemProvider], completion: @escaping (FileDrop) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var fileURLs: [URL] = []
        var sourcePaneSide: PaneSide?

        for provider in providers where canLoadFileDropProvider(provider) {
            group.enter()

            if provider.hasItemConformingToTypeIdentifier(FileDragPayload.typeIdentifier) {
                provider.loadDataRepresentation(forTypeIdentifier: FileDragPayload.typeIdentifier) { data, _ in
                    if let data,
                       let payload = FileDragPayload.decoded(from: data) {
                        lock.withLock {
                            sourcePaneSide = sourcePaneSide ?? payload.sourcePaneSide
                            fileURLs.append(contentsOf: payload.fileURLs)
                        }
                    }
                    group.leave()
                }
            } else if let typeIdentifier = externalFileTypeIdentifier(for: provider) {
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                    let loadedFileURLs = decodedFileURLs(from: item)

                    if !loadedFileURLs.isEmpty {
                        lock.withLock {
                            fileURLs.append(contentsOf: loadedFileURLs)
                        }
                    }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(FileDrop(sourcePaneSide: sourcePaneSide, fileURLs: fileURLs))
        }
    }

    private func decodedFileURLs(from item: NSSecureCoding?) -> [URL] {
        if let url = item as? URL {
            return url.isFileURL ? [url] : []
        }

        if let url = item as? NSURL {
            let swiftURL = url as URL
            return swiftURL.isFileURL ? [swiftURL] : []
        }

        if let urls = item as? [URL] {
            return urls.filter(\.isFileURL)
        }

        if let urls = item as? [NSURL] {
            return urls
                .map { $0 as URL }
                .filter(\.isFileURL)
        }

        if let paths = item as? [String] {
            return paths.compactMap(fileURL(from:))
        }

        if let data = item as? Data,
           let fileURLs = fileURLs(from: data) {
            return fileURLs
        }

        if let string = item as? String {
            return fileURL(from: string).map { [$0] } ?? []
        }

        return []
    }

    private func fileURLs(from data: Data) -> [URL]? {
        if let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let paths = propertyList as? [String] {
            return paths.compactMap(fileURL(from:))
        }

        if let string = String(data: data, encoding: .utf8),
           let fileURL = fileURL(from: string) {
            return [fileURL]
        }

        return nil
    }

    private func fileURL(from string: String) -> URL? {
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmedString),
           url.isFileURL {
            return url
        }

        if trimmedString.hasPrefix("/") {
            return URL(fileURLWithPath: trimmedString)
        }

        return nil
    }

    private func uniqueFileURLs(_ urls: [URL]) -> [URL] {
        var seenURLs: Set<URL> = []

        return urls.filter { url in
            guard !seenURLs.contains(url) else {
                return false
            }

            seenURLs.insert(url)
            return true
        }
    }

    private func itemCountDescription(_ count: Int) -> String {
        let itemText = count == 1 ? "item" : "items"
        return "\(count) \(itemText)"
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
    let paneSide: PaneSide?
    let isOperationInProgress: Bool
    let onSelect: () -> Void
    let onDragItems: () -> [FileItem]
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
    let onDropFiles: ([NSItemProvider], URL) -> Bool
    let onFileDropTargetedChange: (Bool) -> Void
    let compressItemCount: Int

    @State private var isHovered = false
    @State private var isFileDropTargeted = false

    private var dropVisualState: FileDropVisualState {
        guard isFileDropTargeted else {
            return .none
        }

        return item.isDirectory ? .valid : .invalid
    }

    private var rowBackground: Color {
        switch dropVisualState {
        case .valid:
            return CatppuccinMochaTheme.accent.opacity(0.14)
        case .invalid:
            return CatppuccinMochaTheme.destructive.opacity(0.12)
        case .none:
            break
        }

        if isSelected {
            return isPaneActive
                ? CatppuccinMochaTheme.rowSelectedBackground
                : CatppuccinMochaTheme.surface1.opacity(0.58)
        }

        if isHovered {
            return CatppuccinMochaTheme.surface1.opacity(0.58)
        }

        return Color.clear
    }

    private var rowBorder: Color {
        switch dropVisualState {
        case .valid:
            return CatppuccinMochaTheme.accentSecondary.opacity(0.78)
        case .invalid:
            return CatppuccinMochaTheme.destructive.opacity(0.72)
        case .none:
            break
        }

        return isSelected ? CatppuccinMochaTheme.accent.opacity(0.45) : Color.clear
    }

    private var dropTint: Color {
        switch dropVisualState {
        case .valid:
            return CatppuccinMochaTheme.accentSecondary
        case .invalid:
            return CatppuccinMochaTheme.destructive
        case .none:
            return Color.clear
        }
    }

    private var dropHintTitle: String {
        switch dropVisualState {
        case .valid:
            return "Drop to copy here"
        case .invalid:
            return "Drop into folders only"
        case .none:
            return ""
        }
    }

    private var dropHintSystemImage: String {
        switch dropVisualState {
        case .valid:
            return "folder.fill"
        case .invalid:
            return "nosign"
        case .none:
            return ""
        }
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
        .opacity(isOperationInProgress ? 0.68 : 1)
        .background(
            rowBackground,
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                .stroke(rowBorder, lineWidth: isFileDropTargeted ? CatppuccinMochaTheme.paneBorderWidth : CatppuccinMochaTheme.hairlineBorderWidth)
        }
        .overlay(alignment: .leading) {
            if isFileDropTargeted {
                Capsule()
                    .fill(dropTint)
                    .frame(width: 3, height: 22)
                    .padding(.leading, 3)
            }
        }
        .overlay(alignment: .trailing) {
            if isFileDropTargeted {
                HStack(spacing: 5) {
                    Image(systemName: dropHintSystemImage)
                        .font(.system(size: 10, weight: .semibold))
                    Text(dropHintTitle)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(dropTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    CatppuccinMochaTheme.surface0.opacity(0.94),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(dropTint.opacity(0.28), lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
                }
                .padding(.trailing, 8)
            }
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
        .onDrag {
            dragItemProvider()
        }
        // Folder rows are valid targets. Regular file rows deliberately reject
        // drops so a drag never looks like it might overwrite that file.
        .fileDropTarget(
            enabled: true,
            isTargeted: $isFileDropTargeted,
            perform: { providers in
                guard item.isDirectory else {
                    return false
                }

                return onDropFiles(providers, item.url)
            }
        )
        .onChange(of: isFileDropTargeted) { _, isTargeted in
            onFileDropTargetedChange(isTargeted)
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

    private func dragItemProvider() -> NSItemProvider {
        let draggedItems = onDragItems()
        let provider = NSItemProvider()

        if let firstItem = draggedItems.first {
            provider.suggestedName = firstItem.name

            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                fileOptions: [],
                visibility: .all
            ) { completion in
                completion(firstItem.url, true, nil)
                return nil
            }

            provider.registerObject(firstItem.url as NSURL, visibility: .all)
            registerFileURLDataRepresentations(for: firstItem.url, on: provider)
        }

        let payload = FileDragPayload(
            sourcePaneSide: paneSide,
            fileURLs: draggedItems.map(\.url)
        )

        if let data = payload.encodedData {
            provider.registerDataRepresentation(
                forTypeIdentifier: FileDragPayload.typeIdentifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
        }

        return provider
    }

    private func registerFileURLDataRepresentations(for url: URL, on provider: NSItemProvider) {
        guard let data = url.absoluteString.data(using: .utf8) else {
            return
        }

        for typeIdentifier in [UTType.fileURL.identifier, fileURLPasteboardTypeIdentifier].uniqued() {
            provider.registerDataRepresentation(
                forTypeIdentifier: typeIdentifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
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
                Label("Default", systemImage: "app")
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
            Label("Open With", systemImage: "app.badge")
        }

        Divider()

        Button(role: .destructive) {
            onPrepare()
            onTrash()
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }

        Divider()

        Button {
            onPrepare()
            onGetInfo()
        } label: {
            Label("Get Info", systemImage: "info.circle")
        }

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

        Button {
            onPrepare()
            onShare()
        } label: {
            Label("Share...", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button {
            onPrepare()
            onCopyItems()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
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
    let onShowViewOptions: () -> Void
    let onCopyCurrentFolderPath: () -> Void
    let onRevealCurrentFolder: () -> Void
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

        Divider()

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

        Button {
            onShowViewOptions()
        } label: {
            Label("Show View Options", systemImage: "slider.horizontal.3")
        }

        Divider()

        Button {
            onCopyCurrentFolderPath()
        } label: {
            Label("Copy Current Folder Path", systemImage: "doc.on.clipboard")
        }

        Button {
            onRevealCurrentFolder()
        } label: {
            Label("Reveal Current Folder in Finder", systemImage: "finder")
        }
    }
}

private struct FilePaneViewOptionsView: View {
    @ObservedObject var viewModel: FilePaneViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("View Options")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)

                Text(viewModel.currentURL.path)
                    .font(.system(size: 12))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Show Hidden Files", isOn: includeHiddenFilesBinding)
                    .toggleStyle(.checkbox)

                optionPicker(
                    title: "Sort By",
                    selection: $viewModel.sortOption,
                    options: FileSortOption.allCases
                ) { option in
                    option.displayName
                }

                optionPicker(
                    title: "Sort Direction",
                    selection: $viewModel.sortDirection,
                    options: FileSortDirection.allCases
                ) { direction in
                    direction.displayName
                }

                Toggle("Directories First", isOn: $viewModel.directoriesFirst)
                    .toggleStyle(.checkbox)
            }
            .font(.system(size: 13))
            .foregroundStyle(CatppuccinMochaTheme.primaryText)

            HStack {
                Spacer()

                Button("Close") {
                    onClose()
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 380)
        .background(CatppuccinMochaTheme.mantle)
        .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }

    private var includeHiddenFilesBinding: Binding<Bool> {
        Binding {
            viewModel.includeHiddenFiles
        } set: { shouldIncludeHiddenFiles in
            Task {
                await viewModel.setIncludeHiddenFiles(shouldIncludeHiddenFiles)
            }
        }
    }

    private func optionPicker<Option: Hashable, Label: StringProtocol>(
        title: String,
        selection: Binding<Option>,
        options: [Option],
        label: @escaping (Option) -> Label
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(CatppuccinMochaTheme.mutedText)

            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option))
                        .tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
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

    @ViewBuilder
    func fileDropTarget(
        enabled: Bool,
        isTargeted: Binding<Bool>,
        perform: @escaping ([NSItemProvider]) -> Bool
    ) -> some View {
        if enabled {
            onDrop(
                of: fileDropTypeIdentifiers,
                isTargeted: isTargeted,
                perform: perform
            )
        } else {
            self
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seenElements: Set<Element> = []

        return filter { element in
            guard !seenElements.contains(element) else {
                return false
            }

            seenElements.insert(element)
            return true
        }
    }
}
