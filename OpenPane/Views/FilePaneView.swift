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
    static let rowHeight: CGFloat = 31
    static let headerHorizontalPadding = contentPadding + rowHorizontalPadding
    static let columnSpacing: CGFloat = 18
    static let sizeColumnWidth: CGFloat = 92
    static let modifiedColumnWidth: CGFloat = 150
    static let kindColumnWidth: CGFloat = 128
    static let showSizeMinimumWidth: CGFloat = 360
    static let showModifiedDateMinimumWidth: CGFloat = 500
    static let showKindMinimumWidth: CGFloat = 620
}

private struct FilePaneColumnVisibility: Equatable {
    let showsSize: Bool
    let showsModifiedDate: Bool
    let showsKind: Bool

    init(width: CGFloat) {
        showsSize = width >= FilePaneListMetrics.showSizeMinimumWidth
        showsModifiedDate = width >= FilePaneListMetrics.showModifiedDateMinimumWidth
        showsKind = width >= FilePaneListMetrics.showKindMinimumWidth
    }
}

private enum FilePaneTabMetrics {
    static let stripHeight: CGFloat = 38
    static let tabHeight: CGFloat = 32
    static let appendDropTargetHeight: CGFloat = 30
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
private let fileListSelectionCoordinateSpace = "file-list-selection-coordinate-space"

private nonisolated struct FileDrop: Sendable {
    let sourcePaneSide: PaneSide?
    let fileURLs: [URL]
}

private nonisolated final class FileDropAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var fileURLs: [URL] = []
    private var sourcePaneSide: PaneSide?

    func append(_ payload: FileDragPayload) {
        lock.withLock {
            sourcePaneSide = sourcePaneSide ?? payload.sourcePaneSide
            fileURLs.append(contentsOf: payload.fileURLs)
        }
    }

    func append(fileURLs newFileURLs: [URL]) {
        lock.withLock {
            fileURLs.append(contentsOf: newFileURLs)
        }
    }

    func snapshot() -> FileDrop {
        lock.withLock {
            FileDrop(sourcePaneSide: sourcePaneSide, fileURLs: fileURLs)
        }
    }
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
    var onMoveTab: @MainActor @Sendable (FilePaneTab.ID, PaneSide, PaneSide, Int?) -> Void = { _, _, _, _ in }
    var onRenameSelected: () -> Void = {}
    var onTrashSelected: () -> Void = {}
    var onDuplicateSelected: () -> Void = {}
    var onDuplicate: (FileItem) -> Void = { _ in }
    var onCompress: (FileItem) -> Void = { _ in }
    var onCreateFolder: () -> Void = {}
    var onCreateFile: () -> Void = {}
    var onPaste: () -> Void = {}
    var onStatusMessage: (String) -> Void = { _ in }
    var onDropFiles: ([URL], PaneSide?, URL) -> Void = { _, _, _ in }
    var onMountNetworkURLs: ([URL]) -> Void = { _ in }

    @State private var isTabAppendDropTargeted = false
    @State private var targetedTabID: FilePaneTab.ID?
    @State private var isPaneFileDropTargeted = false
    @State private var targetedFolderDropID: FileItem.ID?
    @State private var infoItem: FileItem?
    @State private var isShowingViewOptions = false
    @State private var fileListFocusRequest = 0
    @State private var isFileListKeyboardFocused = false
    @State private var fileListRowFrames: [FileItem.ID: CGRect] = [:]
    @State private var marqueeSelectionStartPoint: CGPoint?
    @State private var marqueeSelectionRect: CGRect?
    @State private var marqueeSelectionBaseIDs: Set<FileItem.ID> = []
    @State private var marqueeAddsToSelection = false

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
        if (viewModel.isLoading || viewModel.isSearchingSubtree) && viewModel.visibleItems.isEmpty {
            return .loading
        }

        if let errorMessage = viewModel.errorMessage,
           viewModel.visibleItems.isEmpty {
            return .error(errorMessage)
        }

        guard viewModel.visibleItems.isEmpty else {
            return nil
        }

        if viewModel.isShowingRecursiveSearchResults {
            return .emptyRecursiveSearch
        }

        if viewModel.searchMode == .filter,
           !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .emptySearch
        }

        return .emptyFolder
    }

    private var shouldShowErrorBanner: Bool {
        viewModel.errorMessage != nil &&
            !viewModel.visibleItems.isEmpty &&
            !viewModel.isLoading
    }

    private var isAnyTabDropTargeted: Bool {
        isTabAppendDropTargeted || targetedTabID != nil
    }

    private var paneAccessibilityIdentifier: String {
        switch paneSide {
        case .left:
            return "left-file-pane"
        case .right:
            return "right-file-pane"
        case nil:
            return "file-pane"
        }
    }

    private var fileListAccessibilityIdentifier: String {
        switch paneSide {
        case .left:
            return "left-file-list"
        case .right:
            return "right-file-list"
        case nil:
            return "file-list"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            tabBar
                .padding(.horizontal, 10)
                .padding(.top, 10)

            paneHeader
                .padding(.horizontal, 12)

            if viewModel.isFileBackedLocation {
                toolbar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            if viewModel.isFileBackedLocation,
               shouldShowErrorBanner,
               let errorMessage = viewModel.errorMessage {
                paneErrorBanner(errorMessage)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            paneContent
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
        .modifier(
            FilePaneActivationModifier(
                accessibilityIdentifier: paneAccessibilityIdentifier,
                onActivate: onActivate
            )
        )
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
        .onChange(of: isActive) { _, isActive in
            if isActive {
                requestFileListFocus(activatePane: false)
            }
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

    @ViewBuilder
    private var paneContent: some View {
        if viewModel.isFileBackedLocation {
            ZStack {
                fileTable

                if let paneContentState {
                    paneStateView(paneContentState)
                        .transition(.opacity)
                }
            }
        } else {
            NetworkPageView(onMount: onMountNetworkURLs)
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
                viewModel.isSearchingSubtree ? "Searching" : "Loading folder",
                viewModel.isSearchingSubtree
                    ? "Searching for “\(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines))”..."
                    : "Reading \(viewModel.currentURL.openPaneDisplayName)...",
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
                    Text(viewModel.currentLocation.displayName)
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

                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(CatppuccinMochaTheme.accent)
                            .accessibilityLabel("Loading folder")
                    }
                }

                PathBarView(path: viewModel.currentLocation.pathText) { url in
                    Task {
                        await viewModel.setDirectory(url)
                    }
                }
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
        .frame(
            maxWidth: .infinity,
            minHeight: FilePaneTabMetrics.stripHeight,
            maxHeight: FilePaneTabMetrics.stripHeight,
            alignment: .leading
        )
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
            .frame(
                maxWidth: .infinity,
                minHeight: FilePaneTabMetrics.appendDropTargetHeight,
                maxHeight: FilePaneTabMetrics.appendDropTargetHeight
            )
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
        .frame(height: FilePaneTabMetrics.tabHeight)
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
            location: tab.location
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
        ViewThatFits(in: .horizontal) {
            toolbarControlRow

            ScrollView(.horizontal, showsIndicators: false) {
                toolbarControlRow
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .controlSize(.small)
        .foregroundStyle(CatppuccinMochaTheme.primaryText)
    }

    private var toolbarControlRow: some View {
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
            .disabled(viewModel.selectedItems.count != 1)

            Button {
                viewModel.revealSelectedItemsInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .disabled(viewModel.selectedItems.isEmpty)

            searchControls
                .layoutPriority(1)
        }
    }

    private var searchControls: some View {
        HStack(spacing: 8) {
            Picker("Search mode", selection: $viewModel.searchMode) {
                ForEach(FilePaneSearchMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)

            searchField

            if viewModel.isSearchingSubtree {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching…")
                        .font(.system(size: 11))
                        .foregroundStyle(CatppuccinMochaTheme.mutedText)
                }
            } else if let statusText = viewModel.searchStatusText {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(CatppuccinMochaTheme.mutedText)
                    .lineLimit(1)
            }

            if viewModel.isShowingRecursiveSearchResults || !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }

            if viewModel.searchMode.isSubtreeSearch {
                Button("Search") {
                    Task {
                        await viewModel.performRecursiveSearch()
                    }
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(
                    viewModel.isSearchingSubtree ||
                        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            Button("Search Subtree") {
                Task {
                    await viewModel.triggerSubtreeSearch()
                }
            }
            .openPaneKeyboardShortcut(keyboardShortcutStore.shortcut(for: .searchSubtree))
            .disabled(!isActive)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CatppuccinMochaTheme.mutedText)

            TextField(viewModel.searchMode.placeholder, text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)
                .onSubmit {
                    Task {
                        await viewModel.performRecursiveSearch()
                    }
                }
        }
        .padding(.horizontal, 9)
        .frame(minWidth: 120, idealWidth: 180, maxWidth: 220, minHeight: 28, maxHeight: 28)
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
        GeometryReader { geometry in
            let columnVisibility = FilePaneColumnVisibility(width: geometry.size.width)
            let rowHeight = viewModel.isShowingContentSearchResults ? 44.0 : FilePaneListMetrics.rowHeight
            let pageSize = max(
                1,
                Int((geometry.size.height - rowHeight) / (rowHeight + 2)) - 1
            )

            ScrollViewReader { scrollProxy in
                VStack(spacing: 0) {
                    fileListHeader(columnVisibility: columnVisibility)

                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(viewModel.visibleItems) { item in
                                FilePaneRowView(
                                item: item,
                                contentSearchDescription: viewModel.recursiveSearchContentDescription(for: item),
                                calculatedSizeText: viewModel.calculatedFolderSizeText(for: item),
                                columnVisibility: columnVisibility,
                                isSelected: viewModel.selectedItems.contains(item),
                                isKeyboardFocused: isActive &&
                                    isFileListKeyboardFocused &&
                                    viewModel.focusedFileListItemID == item.id,
                                isPaneActive: isActive,
                                paneSide: paneSide,
                                isOperationInProgress: isPerformingOperation,
                                onSelect: {
                                    selectItem(item)
                                },
                                onDragItems: {
                                    requestFileListFocus()
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
                                applicationOptions: {
                                    viewModel.applicationsAvailableToOpen(item)
                                },
                                onOpenWithApplication: { applicationURL in
                                    Task {
                                        await viewModel.open(item, withApplication: applicationURL)
                                    }
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
                                onCalculateFolderSize: {
                                    viewModel.calculateFolderSizeForContextMenu(clickedItem: item)
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
                                compressItemCount: {
                                    viewModel.contextMenuTargetItems(clickedItem: item).count
                                }
                                )
                                .equatable()
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: FileListRowFramePreferenceKey.self,
                                            value: [
                                                item.id: proxy.frame(
                                                    in: .named(fileListSelectionCoordinateSpace)
                                                )
                                            ]
                                        )
                                    }
                                }
                                .id(item.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(FilePaneListMetrics.contentPadding)
                    }
                    .background(CatppuccinMochaTheme.base)
                    .background {
                        FileListKeyboardFocusView(
                            focusRequest: fileListFocusRequest,
                            isActive: isActive,
                            onFocusChange: { isFocused in
                                isFileListKeyboardFocused = isFocused
                            },
                            onKeyDown: { event in
                                handleFileListKeyDown(event, pageSize: pageSize)
                            }
                        )
                    }
                    .coordinateSpace(name: fileListSelectionCoordinateSpace)
                    .overlay {
                        if isPaneFileDropTargeted && targetedFolderDropID == nil {
                            paneDropTargetOverlay
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        marqueeSelectionOverlay
                    }
                    .onDrop(
                        of: fileDropTypeIdentifiers,
                        isTargeted: $isPaneFileDropTargeted,
                        perform: { providers in
                            handleFileDrop(providers, targetDirectory: viewModel.currentURL)
                        }
                    )
                    .onPreferenceChange(FileListRowFramePreferenceKey.self) { rowFrames in
                        fileListRowFrames = rowFrames
                    }
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
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            requestFileListFocus()
                        }
                    )
                    .simultaneousGesture(marqueeSelectionGesture)
                    .onRightClickInside {
                        requestFileListFocus()
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onChange(of: viewModel.focusedFileListItemID) { _, focusedID in
                    guard let focusedID else {
                        return
                    }

                    withAnimation(.easeOut(duration: 0.08)) {
                        scrollProxy.scrollTo(focusedID, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CatppuccinMochaTheme.base)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(fileListAccessibilityIdentifier)
    }

    private func fileListHeader(columnVisibility: FilePaneColumnVisibility) -> some View {
        HStack(spacing: FilePaneListMetrics.columnSpacing) {
            sortHeader(.name)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            if columnVisibility.showsSize {
                sortHeader(.size)
                    .frame(width: FilePaneListMetrics.sizeColumnWidth, alignment: .trailing)
            }

            if columnVisibility.showsModifiedDate {
                sortHeader(.modifiedDate)
                    .frame(width: FilePaneListMetrics.modifiedColumnWidth, alignment: .leading)
            }

            if columnVisibility.showsKind {
                sortHeader(.kind)
                    .frame(width: FilePaneListMetrics.kindColumnWidth, alignment: .leading)
            }
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
                    title: "Drop to place here",
                    subtitle: "Uses your file drop action",
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
        viewModel.applyHeaderSort(option)
    }

    private var marqueeSelectionGesture: some Gesture {
        DragGesture(
            minimumDistance: 6,
            coordinateSpace: .named(fileListSelectionCoordinateSpace)
        )
        .onChanged { value in
            updateMarqueeSelection(with: value)
        }
        .onEnded { _ in
            resetMarqueeSelection()
        }
    }

    private func updateMarqueeSelection(with value: DragGesture.Value) {
        guard viewModel.isFileBackedLocation else {
            return
        }

        if marqueeSelectionStartPoint == nil {
            guard !fileListRowFrames.values.contains(where: { $0.contains(value.startLocation) }) else {
                return
            }

            let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            marqueeAddsToSelection = modifiers.contains(.command) || modifiers.contains(.shift)
            marqueeSelectionBaseIDs = marqueeAddsToSelection
                ? Set(viewModel.selectedItems.map(\.id))
                : []
            marqueeSelectionStartPoint = value.startLocation
        }

        guard let startPoint = marqueeSelectionStartPoint else {
            return
        }

        let selectionRect = CGRect(
            x: min(startPoint.x, value.location.x),
            y: min(startPoint.y, value.location.y),
            width: abs(value.location.x - startPoint.x),
            height: abs(value.location.y - startPoint.y)
        )
        let selectedIDs = Set(
            fileListRowFrames.compactMap { itemID, frame in
                selectionRect.intersects(frame) ? itemID : nil
            }
        )
        let effectiveSelectionIDs = marqueeSelectionBaseIDs.union(selectedIDs)

        marqueeSelectionRect = selectionRect
        viewModel.selectFileListItems(
            withIDs: effectiveSelectionIDs,
            addingToSelection: false
        )
    }

    private func resetMarqueeSelection() {
        marqueeSelectionStartPoint = nil
        marqueeSelectionRect = nil
        marqueeSelectionBaseIDs = []
        marqueeAddsToSelection = false
    }

    @ViewBuilder
    private var marqueeSelectionOverlay: some View {
        if let marqueeSelectionRect {
            Rectangle()
                .fill(CatppuccinMochaTheme.accent.opacity(0.12))
                .overlay {
                    Rectangle()
                        .stroke(
                            CatppuccinMochaTheme.accent.opacity(0.75),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                }
                .frame(
                    width: max(1, marqueeSelectionRect.width),
                    height: max(1, marqueeSelectionRect.height)
                )
                .position(
                    x: marqueeSelectionRect.midX,
                    y: marqueeSelectionRect.midY
                )
                .allowsHitTesting(false)
        }
    }

    private func selectItem(_ item: FileItem) {
        requestFileListFocus()
        let modifiers = NSEvent.modifierFlags
        viewModel.selectFileListItem(
            item,
            commandModifier: modifiers.contains(.command),
            shiftModifier: modifiers.contains(.shift)
        )
    }

    private func selectItemForContextMenu(_ item: FileItem) {
        requestFileListFocus()
        viewModel.selectForContextMenu(item)
    }

    private func requestFileListFocus(activatePane: Bool = true) {
        if activatePane {
            onActivate()
        }
        fileListFocusRequest += 1
    }

    private func handleFileListKeyDown(_ event: NSEvent, pageSize: Int) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let extendsSelection = modifiers.contains(.shift)

        if keyboardShortcutStore.shortcut(for: .open).matches(event) {
            Task {
                await viewModel.openFocusedFileListItem()
            }
            return true
        }

        if keyboardShortcutStore.shortcut(for: .preview).matches(event) {
            viewModel.previewFocusedFileListItem()
            return true
        }

        if keyboardShortcutStore.shortcut(for: .copyFiles).matches(event) {
            let copiedItemCount = viewModel.copySelectedItemsToPasteboard()
            if copiedItemCount > 0 {
                onStatusMessage(copyItemsStatusMessage(itemCount: copiedItemCount))
            }
            return true
        }

        if keyboardShortcutStore.shortcut(for: .pasteFiles).matches(event) {
            onPaste()
            return true
        }

        if keyboardShortcutStore.shortcut(for: .selectAllFiles).matches(event) {
            viewModel.selectAllVisibleItems()
            return true
        }

        if keyboardShortcutStore.shortcut(for: .duplicateFiles).matches(event) {
            onDuplicateSelected()
            return true
        }

        if keyboardShortcutStore.shortcut(for: .newFile).matches(event) {
            onCreateFile()
            return true
        }

        let focusedID: FileItem.ID?
        switch event.keyCode {
        case 126:
            focusedID = viewModel.moveFileListFocus(by: -1, extendingSelection: extendsSelection)
        case 125:
            focusedID = viewModel.moveFileListFocus(by: 1, extendingSelection: extendsSelection)
        case 115:
            focusedID = viewModel.moveFileListFocus(toIndex: 0, extendingSelection: extendsSelection)
        case 119:
            focusedID = viewModel.moveFileListFocus(
                toIndex: viewModel.visibleItems.count - 1,
                extendingSelection: extendsSelection
            )
        case 116:
            focusedID = viewModel.moveFileListFocus(by: -pageSize, extendingSelection: extendsSelection)
        case 121:
            focusedID = viewModel.moveFileListFocus(by: pageSize, extendingSelection: extendsSelection)
        default:
            focusedID = nil
        }

        if focusedID != nil {
            return true
        }

        let disallowedTypeAheadModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard modifiers.intersection(disallowedTypeAheadModifiers).isEmpty,
              let characters = event.characters,
              !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }

        return viewModel.selectFileListItemByTypeAhead(characters) != nil
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

    private func loadDroppedFiles(
        from providers: [NSItemProvider],
        completion: @escaping @MainActor @Sendable (FileDrop) -> Void
    ) {
        let group = DispatchGroup()
        let accumulator = FileDropAccumulator()

        for provider in providers where canLoadFileDropProvider(provider) {
            group.enter()

            if provider.hasItemConformingToTypeIdentifier(FileDragPayload.typeIdentifier) {
                provider.loadDataRepresentation(forTypeIdentifier: FileDragPayload.typeIdentifier) { data, _ in
                    if let data,
                       let payload = FileDragPayload.decoded(from: data) {
                        accumulator.append(payload)
                    }
                    group.leave()
                }
            } else if let typeIdentifier = externalFileTypeIdentifier(for: provider) {
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                    let loadedFileURLs = Self.decodedFileURLs(from: item)

                    if !loadedFileURLs.isEmpty {
                        accumulator.append(fileURLs: loadedFileURLs)
                    }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(accumulator.snapshot())
        }
    }

    private nonisolated static func decodedFileURLs(from item: NSSecureCoding?) -> [URL] {
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
            return paths.compactMap { fileURL(from: $0) }
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

    private nonisolated static func fileURLs(from data: Data) -> [URL]? {
        if let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let paths = propertyList as? [String] {
            return paths.compactMap { fileURL(from: $0) }
        }

        if let string = String(data: data, encoding: .utf8),
           let fileURL = fileURL(from: string) {
            return [fileURL]
        }

        return nil
    }

    private nonisolated static func fileURL(from string: String) -> URL? {
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
            let identityURL = url
                .resolvingSymlinksInPath()
                .standardizedFileURL

            guard !seenURLs.contains(identityURL) else {
                return false
            }

            seenURLs.insert(identityURL)
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

private struct FilePaneRowContent: View, Equatable {
    let item: FileItem
    let contentSearchDescription: String?
    let calculatedSizeText: String?
    let columnVisibility: FilePaneColumnVisibility

    private var nameColor: Color {
        item.isDirectory ? CatppuccinMochaTheme.lavender : CatppuccinMochaTheme.primaryText
    }

    var body: some View {
        HStack(spacing: FilePaneListMetrics.columnSpacing) {
            HStack(spacing: 8) {
                FileIconImage(item: item)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: item.isDirectory ? .medium : .regular))
                        .foregroundStyle(nameColor)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let contentSearchDescription {
                        Text(contentSearchDescription)
                            .font(.system(size: 10))
                            .foregroundStyle(CatppuccinMochaTheme.mutedText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .clipped()

            if columnVisibility.showsSize {
                Text(calculatedSizeText ?? item.formattedSize)
                    .lineLimit(1)
                    .frame(width: FilePaneListMetrics.sizeColumnWidth, alignment: .trailing)
            }

            if columnVisibility.showsModifiedDate {
                Text(item.formattedModifiedDate)
                    .lineLimit(1)
                    .frame(width: FilePaneListMetrics.modifiedColumnWidth, alignment: .leading)
            }

            if columnVisibility.showsKind {
                Text(item.kindDescription)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: FilePaneListMetrics.kindColumnWidth, alignment: .leading)
            }
        }
    }
}

private struct FilePaneRowView: View {
    let item: FileItem
    let contentSearchDescription: String?
    let calculatedSizeText: String?
    let columnVisibility: FilePaneColumnVisibility
    let isSelected: Bool
    let isKeyboardFocused: Bool
    let isPaneActive: Bool
    let paneSide: PaneSide?
    let isOperationInProgress: Bool
    let onSelect: () -> Void
    let onDragItems: () -> [FileItem]
    let onContextSelect: () -> Void
    let onOpen: () -> Void
    let applicationOptions: () -> [ApplicationOption]
    let onOpenWithApplication: (URL) -> Void
    let onChooseApplication: () -> Void
    let onShare: () -> Void
    let onCopyItems: () -> Void
    let onGetInfo: () -> Void
    let onCalculateFolderSize: () -> Void
    let onRename: () -> Void
    let onTrash: () -> Void
    let onDuplicate: () -> Void
    let onCompress: () -> Void
    let onReveal: () -> Void
    let onPreview: () -> Void
    let onCopyText: (FileItemCopyTextFormat) -> Void
    let onDropFiles: ([NSItemProvider], URL) -> Bool
    let onFileDropTargetedChange: (Bool) -> Void
    let compressItemCount: () -> Int

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

        if isKeyboardFocused {
            return CatppuccinMochaTheme.accent.opacity(0.10)
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

        if isKeyboardFocused {
            return CatppuccinMochaTheme.accentSecondary.opacity(0.92)
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
            return "Drop to place here"
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

    var body: some View {
        FilePaneRowContent(
            item: item,
            contentSearchDescription: contentSearchDescription,
            calculatedSizeText: calculatedSizeText,
            columnVisibility: columnVisibility
        )
        .equatable()
        .font(.system(size: 12))
        .foregroundStyle(CatppuccinMochaTheme.subtext0)
        .padding(.horizontal, FilePaneListMetrics.rowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: contentSearchDescription == nil ? FilePaneListMetrics.rowHeight : 44)
        .opacity(isOperationInProgress ? 0.68 : 1)
        .background(
            rowBackground,
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                .stroke(
                    rowBorder,
                    lineWidth: isFileDropTargeted || isKeyboardFocused
                        ? CatppuccinMochaTheme.paneBorderWidth
                        : CatppuccinMochaTheme.hairlineBorderWidth
                )
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
            if isFileDropTargeted && columnVisibility.showsSize {
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
        // Only folder rows install a drop target. Giving every file row its own
        // target makes resize and event handling scale with the full file count.
        .fileDropTarget(
            enabled: item.isDirectory,
            isTargeted: $isFileDropTargeted,
            perform: { providers in
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
                onCalculateFolderSize: onCalculateFolderSize,
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
            registerFileURLDataRepresentations(for: draggedItems.map(\.url), on: provider)
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

    private func registerFileURLDataRepresentations(for urls: [URL], on provider: NSItemProvider) {
        guard let firstURL = urls.first,
              let data = firstURL.absoluteString.data(using: .utf8) else {
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

        let paths = urls.map(\.path)
        if let filenamesData = try? PropertyListSerialization.data(
            fromPropertyList: paths,
            format: .binary,
            options: 0
        ) {
            provider.registerDataRepresentation(
                forTypeIdentifier: fileNamesPasteboardTypeIdentifier,
                visibility: .all
            ) { completion in
                completion(filenamesData, nil)
                return nil
            }
        }
    }
}

extension FilePaneRowView: Equatable {
    static func == (lhs: FilePaneRowView, rhs: FilePaneRowView) -> Bool {
        lhs.item == rhs.item &&
            lhs.contentSearchDescription == rhs.contentSearchDescription &&
            lhs.calculatedSizeText == rhs.calculatedSizeText &&
            lhs.columnVisibility == rhs.columnVisibility &&
            lhs.isSelected == rhs.isSelected &&
            lhs.isKeyboardFocused == rhs.isKeyboardFocused &&
            lhs.isPaneActive == rhs.isPaneActive &&
            lhs.paneSide == rhs.paneSide &&
            lhs.isOperationInProgress == rhs.isOperationInProgress
    }
}

private struct FilePaneActivationModifier: ViewModifier {
    let accessibilityIdentifier: String
    let onActivate: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    onActivate()
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityAction {
                onActivate()
            }
    }
}

private struct FileIconImage: View {
    let item: FileItem

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(item.isDirectory ? CatppuccinMochaTheme.lavender : CatppuccinMochaTheme.mutedText)
            }
        }
        .frame(width: 17, height: 17)
        .opacity(item.isDirectory ? 1 : 0.92)
        .layoutPriority(1)
        .task(id: item.id) {
            if let cachedIcon = FileIconService.shared.cachedIcon(for: item) {
                icon = cachedIcon
                return
            }

            let loadedIcon = await FileIconService.shared.icon(for: item)
            guard !Task.isCancelled else {
                return
            }
            icon = loadedIcon
        }
    }
}

private struct FileItemContextMenu: View {
    let item: FileItem
    let isPaneActive: Bool
    let onPrepare: () -> Void
    let onOpen: () -> Void
    let applicationOptions: () -> [ApplicationOption]
    let onOpenWithApplication: (URL) -> Void
    let onChooseApplication: () -> Void
    let onShare: () -> Void
    let onCopyItems: () -> Void
    let onGetInfo: () -> Void
    let onCalculateFolderSize: () -> Void
    let onRename: () -> Void
    let onTrash: () -> Void
    let onDuplicate: () -> Void
    let onCompress: () -> Void
    let onPreview: () -> Void
    let onReveal: () -> Void
    let onCopyText: (FileItemCopyTextFormat) -> Void
    let compressItemCount: () -> Int

    var body: some View {
        Button {
            onPrepare()
            onOpen()
        } label: {
            Label("Open", systemImage: "arrow.forward")
        }

        Menu {
            OpenWithMenuContent(
                applicationOptions: applicationOptions,
                onPrepare: onPrepare,
                onOpen: onOpen,
                onOpenWithApplication: onOpenWithApplication,
                onChooseApplication: onChooseApplication
            )
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

        if item.isDirectory {
            Button {
                onPrepare()
                onCalculateFolderSize()
            } label: {
                Label("Calculate Folder Size", systemImage: "sum")
            }
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
        let compressItemCount = compressItemCount()

        if compressItemCount > 1 {
            return "Compress \(compressItemCount) Items"
        }

        return "Compress \"\(item.displayName)\""
    }
}

private struct OpenWithMenuContent: View {
    let applicationOptions: () -> [ApplicationOption]
    let onPrepare: () -> Void
    let onOpen: () -> Void
    let onOpenWithApplication: (URL) -> Void
    let onChooseApplication: () -> Void

    var body: some View {
        let options = applicationOptions()

        Button {
            onPrepare()
            onOpen()
        } label: {
            Label("Default", systemImage: "app")
        }

        if !options.isEmpty {
            Divider()

            ForEach(options) { application in
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

private struct FileListKeyboardFocusView: NSViewRepresentable {
    let focusRequest: Int
    let isActive: Bool
    let onFocusChange: (Bool) -> Void
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> FileListKeyboardNSView {
        let view = FileListKeyboardNSView()
        view.onFocusChange = onFocusChange
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: FileListKeyboardNSView, context: Context) {
        nsView.onFocusChange = onFocusChange
        nsView.onKeyDown = onKeyDown
        nsView.updateFocusRequest(focusRequest, isActive: isActive)
    }
}

private final class FileListKeyboardNSView: NSView {
    var onFocusChange: (Bool) -> Void = { _ in }
    var onKeyDown: (NSEvent) -> Bool = { _ in false }

    private var focusRequest = 0
    private var fulfilledFocusRequest = -1
    private var isActive = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        fulfillFocusRequestIfNeeded()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChange(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChange(false)
        }
        return didResignFirstResponder
    }

    override func keyDown(with event: NSEvent) {
        if !onKeyDown(event) {
            super.keyDown(with: event)
        }
    }

    func updateFocusRequest(_ focusRequest: Int, isActive: Bool) {
        self.focusRequest = focusRequest
        self.isActive = isActive
        fulfillFocusRequestIfNeeded()
    }

    private func fulfillFocusRequestIfNeeded() {
        guard isActive,
              focusRequest != fulfilledFocusRequest,
              let window else {
            return
        }

        fulfilledFocusRequest = focusRequest
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self,
                  self.isActive,
                  self.focusRequest == self.fulfilledFocusRequest else {
                return
            }

            window?.makeFirstResponder(self)
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

}

private struct FileListRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [FileItem.ID: CGRect] = [:]

    static func reduce(
        value: inout [FileItem.ID: CGRect],
        nextValue: () -> [FileItem.ID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
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
