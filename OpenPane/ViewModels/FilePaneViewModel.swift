//
//  FilePaneViewModel.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Combine
import Foundation

nonisolated enum FileItemCopyTextFormat: Sendable {
    case absolutePath
    case fileURL
    case name
}

nonisolated enum FileSortOption: String, CaseIterable, Identifiable, Sendable {
    case name
    case size
    case modifiedDate
    case kind

    var id: Self {
        self
    }

    var displayName: String {
        switch self {
        case .name:
            return "Name"
        case .size:
            return "Size"
        case .modifiedDate:
            return "Modified Date"
        case .kind:
            return "Kind"
        }
    }

    var columnTitle: String {
        switch self {
        case .modifiedDate:
            return "Modified"
        default:
            return displayName
        }
    }
}

nonisolated enum FileSortDirection: String, CaseIterable, Identifiable, Sendable {
    case ascending
    case descending

    var id: Self {
        self
    }

    var displayName: String {
        switch self {
        case .ascending:
            return "Ascending"
        case .descending:
            return "Descending"
        }
    }
}

@MainActor
final class FilePaneViewModel: ObservableObject {
    @Published var currentURL: URL {
        didSet {
            updateActiveTab { tab in
                tab.currentURL = currentURL
            }
        }
    }

    @Published var items: [FileItem] {
        didSet {
            updateActiveTab { tab in
                tab.items = items
            }
        }
    }

    @Published var selectedItems: Set<FileItem> {
        didSet {
            updateActiveTab { tab in
                tab.selectedItems = selectedItems
            }
        }
    }

    @Published var tabs: [FilePaneTab]
    @Published var activeTabID: FilePaneTab.ID
    @Published var isLoading: Bool
    @Published var errorMessage: String?
    @Published var includeHiddenFiles: Bool
    @Published var searchText: String
    @Published var sortOption: FileSortOption
    @Published var sortDirection: FileSortDirection
    @Published var directoriesFirst: Bool
    @Published var recursiveSearchResults: [FileItem]
    @Published var isShowingRecursiveSearchResults: Bool

    private let fileBrowserService: any FileBrowserServicing
    private let fileSearchService: any FileSearchServicing
    private let workspaceService: any WorkspaceServicing
    private let quickLookPreviewService: any QuickLookPreviewServicing

    var filteredItems: [FileItem] {
        let filteredItems: [FileItem]

        if isShowingRecursiveSearchResults {
            filteredItems = recursiveSearchResults
        } else {
            let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedSearchText.isEmpty {
                filteredItems = items
            } else {
                filteredItems = items.filter { item in
                    item.name.localizedCaseInsensitiveContains(trimmedSearchText)
                }
            }
        }

        return sortedItems(filteredItems)
    }

    init(
        currentURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileBrowserService: any FileBrowserServicing = FileBrowserService(),
        fileSearchService: any FileSearchServicing = FileSearchService(),
        workspaceService: any WorkspaceServicing = WorkspaceService(),
        quickLookPreviewService: (any QuickLookPreviewServicing)? = nil
    ) {
        self.currentURL = currentURL
        self.items = []
        self.selectedItems = []
        let initialTab = FilePaneTab(currentURL: currentURL)
        self.tabs = [initialTab]
        self.activeTabID = initialTab.id
        self.isLoading = false
        self.errorMessage = nil
        self.includeHiddenFiles = false
        self.searchText = ""
        self.sortOption = .name
        self.sortDirection = .ascending
        self.directoriesFirst = true
        self.recursiveSearchResults = []
        self.isShowingRecursiveSearchResults = false
        self.fileBrowserService = fileBrowserService
        self.fileSearchService = fileSearchService
        self.workspaceService = workspaceService
        self.quickLookPreviewService = quickLookPreviewService ?? QuickLookPreviewService.shared
    }

    func loadCurrentDirectory() async {
        isLoading = true
        errorMessage = nil
        clearRecursiveSearch()
        defer {
            isLoading = false
        }

        do {
            items = try await fileBrowserService.contentsOfDirectory(
                at: currentURL,
                includeHiddenFiles: includeHiddenFiles
            )
        } catch {
            items = []
            errorMessage = Self.userReadableError(for: error, at: currentURL)
        }
    }

    func refresh() async {
        await loadCurrentDirectory()
    }

    func newTab() async {
        saveActiveTabState()
        let tab = FilePaneTab(currentURL: currentURL)
        tabs.append(tab)
        applyTab(tab)
        await loadCurrentDirectory()
    }

    func closeTab(_ id: FilePaneTab.ID) async {
        guard tabs.count > 1,
              let closingIndex = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }

        let isClosingActiveTab = id == activeTabID
        tabs.remove(at: closingIndex)

        guard isClosingActiveTab else {
            return
        }

        let nextIndex = min(closingIndex, tabs.count - 1)
        applyTab(tabs[nextIndex])

        if items.isEmpty {
            await loadCurrentDirectory()
        }
    }

    func switchToTab(_ id: FilePaneTab.ID) async {
        guard id != activeTabID,
              let tab = tabs.first(where: { $0.id == id }) else {
            return
        }

        saveActiveTabState()
        applyTab(tab)

        if items.isEmpty {
            await loadCurrentDirectory()
        }
    }

    func detachTab(_ id: FilePaneTab.ID) -> FilePaneTab? {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        saveActiveTabState()
        let removedTab = tabs.remove(at: index)

        if activeTabID == id {
            let nextIndex = min(index, tabs.count - 1)
            applyTab(tabs[nextIndex])
        }

        return removedTab
    }

    func receiveTab(_ tab: FilePaneTab) {
        guard !tabs.contains(where: { $0.id == tab.id }) else {
            return
        }

        saveActiveTabState()
        tabs.append(tab)
        applyTab(tab)
    }

    func performRecursiveSearch(limit: Int = FileSearchService.defaultLimit) async {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSearchText.isEmpty else {
            errorMessage = "Enter a search term."
            return
        }

        isLoading = true
        errorMessage = nil
        selectedItems = []
        defer {
            isLoading = false
        }

        do {
            recursiveSearchResults = try await fileSearchService.search(
                root: currentURL,
                query: trimmedSearchText,
                includeHiddenFiles: includeHiddenFiles,
                limit: limit
            )
            isShowingRecursiveSearchResults = true
        } catch {
            recursiveSearchResults = []
            isShowingRecursiveSearchResults = false
            errorMessage = Self.userReadableError(for: error, at: currentURL)
        }
    }

    func clearRecursiveSearch() {
        recursiveSearchResults = []
        isShowingRecursiveSearchResults = false
        selectedItems = []
    }

    func selectForContextMenu(_ item: FileItem) {
        guard !selectedItems.contains(item) else {
            return
        }

        selectedItems = [item]
    }

    func showPlaceholderError(_ message: String) {
        errorMessage = message
    }

    func copyPath(of item: FileItem) {
        _ = copyTextForContextMenu(clickedItem: item, format: .absolutePath)
    }

    func copyCurrentFolderPath() {
        errorMessage = nil
        workspaceService.copyText(currentURL.path)
    }

    func copyTextForContextMenu(clickedItem: FileItem, format: FileItemCopyTextFormat) -> Int {
        errorMessage = nil
        let targetItems = contextMenuTargetItems(clickedItem: clickedItem)
        let copiedText = targetItems
            .map { copyText(for: $0, format: format) }
            .joined(separator: "\n")

        workspaceService.copyText(copiedText)
        return targetItems.count
    }

    func copyItemsForContextMenu(clickedItem: FileItem) -> Int {
        errorMessage = nil
        let targetItems = contextMenuTargetItems(clickedItem: clickedItem)
        workspaceService.copyFileURLs(targetItems.map(\.url))
        return targetItems.count
    }

    func fileURLsAvailableToPaste() -> [URL] {
        workspaceService.fileURLsForPasteboard()
    }

    func hasFileURLsToPaste() -> Bool {
        !fileURLsAvailableToPaste().isEmpty
    }

    func toggleHiddenFiles() async {
        await setIncludeHiddenFiles(!includeHiddenFiles)
    }

    func setIncludeHiddenFiles(_ includeHiddenFiles: Bool) async {
        guard self.includeHiddenFiles != includeHiddenFiles else {
            return
        }

        self.includeHiddenFiles = includeHiddenFiles

        if isShowingRecursiveSearchResults {
            await performRecursiveSearch()
        } else {
            await refresh()
        }
    }

    func open(_ item: FileItem) async {
        if item.isDirectory {
            await setDirectory(item.url)
            return
        }

        errorMessage = nil

        workspaceService.open(url: item.url)
    }

    func applicationsAvailableToOpen(_ item: FileItem) -> [ApplicationOption] {
        workspaceService.appsAvailableToOpen(url: item.url)
    }

    func open(_ item: FileItem, withApplication applicationURL: URL) {
        errorMessage = nil
        workspaceService.open(url: item.url, withApplication: applicationURL)
    }

    func chooseApplicationToOpen(_ item: FileItem) {
        errorMessage = nil
        workspaceService.chooseApplicationAndOpen(url: item.url)
    }

    func shareForContextMenu(clickedItem: FileItem) {
        errorMessage = nil
        let targetItems = contextMenuTargetItems(clickedItem: clickedItem)

        do {
            try workspaceService.share(urls: targetItems.map(\.url))
        } catch {
            errorMessage = Self.userReadableWorkspaceError(for: error)
        }
    }

    func openSelectedItem() async {
        let selectedItems = Array(self.selectedItems)

        guard selectedItems.count == 1, let selectedItem = selectedItems.first else {
            errorMessage = selectedItems.isEmpty
                ? "Select one item to open."
                : "Select only one item to open."
            return
        }

        await open(selectedItem)
    }

    func revealSelectedItemsInFinder() {
        let selectedItems = Array(self.selectedItems)

        guard !selectedItems.isEmpty else {
            errorMessage = "Select one or more items to reveal in Finder."
            return
        }

        errorMessage = nil
        workspaceService.revealInFinder(urls: selectedItems.map(\.url))
    }

    func revealForContextMenu(clickedItem: FileItem) {
        errorMessage = nil
        workspaceService.revealInFinder(urls: contextMenuTargetItems(clickedItem: clickedItem).map(\.url))
    }

    func revealCurrentFolderInFinder() {
        errorMessage = nil
        workspaceService.revealInFinder(urls: [currentURL])
    }

    func previewSelectedItem() {
        let selectedItems = Array(self.selectedItems)

        guard selectedItems.count == 1, let selectedItem = selectedItems.first else {
            errorMessage = selectedItems.isEmpty
                ? "Select one file to preview."
                : "Select only one file to preview."
            return
        }

        guard !selectedItem.isDirectory else {
            errorMessage = "Select a file to preview."
            return
        }

        errorMessage = nil
        quickLookPreviewService.preview(url: selectedItem.url)
    }

    func goUp() async {
        let parentURL = currentURL.deletingLastPathComponent()
        await setDirectory(parentURL)
    }

    func setDirectory(_ url: URL) async {
        currentURL = url
        selectedItems = []
        clearRecursiveSearch()
        await loadCurrentDirectory()
    }

    private func sortedItems(_ items: [FileItem]) -> [FileItem] {
        return items.sorted { lhs, rhs in
            if directoriesFirst,
               lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            let comparison = compare(lhs, rhs, by: sortOption)

            if comparison != .orderedSame {
                return sortDirection == .ascending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func compare(_ lhs: FileItem, _ rhs: FileItem, by option: FileSortOption) -> ComparisonResult {
        switch option {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .size:
            return compare(lhs.sortSize, rhs.sortSize)
        case .modifiedDate:
            return compare(lhs.sortModifiedDate, rhs.sortModifiedDate)
        case .kind:
            return lhs.kindDescription.localizedStandardCompare(rhs.kindDescription)
        }
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }

        if lhs > rhs {
            return .orderedDescending
        }

        return .orderedSame
    }

    private func applyTab(_ tab: FilePaneTab) {
        activeTabID = tab.id
        recursiveSearchResults = []
        isShowingRecursiveSearchResults = false
        errorMessage = nil
        currentURL = tab.currentURL
        items = tab.items
        selectedItems = tab.selectedItems
    }

    private func saveActiveTabState() {
        updateActiveTab { tab in
            tab.currentURL = currentURL
            tab.items = items
            tab.selectedItems = selectedItems
        }
    }

    private func updateActiveTab(_ update: (inout FilePaneTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            return
        }

        update(&tabs[index])
    }

    func contextMenuTargetItems(clickedItem: FileItem) -> [FileItem] {
        guard selectedItems.contains(clickedItem) else {
            return [clickedItem]
        }

        return selectedItems.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func copyText(for item: FileItem, format: FileItemCopyTextFormat) -> String {
        switch format {
        case .absolutePath:
            item.url.path
        case .fileURL:
            item.url.absoluteString
        case .name:
            item.name
        }
    }

    private static func userReadableError(for error: Error, at url: URL) -> String {
        let directoryName = url.openPaneDisplayName

        if let browserError = error as? FileBrowserError,
           let description = browserError.errorDescription {
            return description
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
            return "You do not have permission to open \(directoryName)."
        }

        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
            return "\(directoryName) could not be found."
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return "Could not load \(directoryName)."
    }

    private static func userReadableWorkspaceError(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return "The action could not be completed."
    }
}
