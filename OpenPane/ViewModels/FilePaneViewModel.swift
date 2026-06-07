//
//  FilePaneViewModel.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Combine
import Foundation

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
    @Published var sortOrder: [KeyPathComparator<FileItem>]
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
        self.sortOrder = []
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

    func open(_ item: FileItem) async {
        if item.isDirectory {
            await setDirectory(item.url)
            return
        }

        errorMessage = nil

        workspaceService.open(url: item.url)
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
        guard !sortOrder.isEmpty else {
            return items
        }

        return items.sorted { lhs, rhs in
            for comparator in sortOrder {
                switch comparator.compare(lhs, rhs) {
                case .orderedAscending:
                    return true
                case .orderedDescending:
                    return false
                case .orderedSame:
                    continue
                }
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
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
}
