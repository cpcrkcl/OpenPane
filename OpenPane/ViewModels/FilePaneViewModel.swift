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
    @Published var currentURL: URL
    @Published var items: [FileItem]
    @Published var selectedItems: Set<FileItem>
    @Published var isLoading: Bool
    @Published var errorMessage: String?
    @Published var includeHiddenFiles: Bool
    @Published var searchText: String
    @Published var recursiveSearchResults: [FileItem]
    @Published var isShowingRecursiveSearchResults: Bool

    private let fileBrowserService: any FileBrowserServicing
    private let fileSearchService: any FileSearchServicing
    private let workspaceService: any WorkspaceServicing
    private let quickLookPreviewService: any QuickLookPreviewServicing

    var filteredItems: [FileItem] {
        if isShowingRecursiveSearchResults {
            return recursiveSearchResults
        }

        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSearchText.isEmpty else {
            return items
        }

        return items.filter { item in
            item.name.localizedCaseInsensitiveContains(trimmedSearchText)
        }
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
        self.isLoading = false
        self.errorMessage = nil
        self.includeHiddenFiles = false
        self.searchText = ""
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
