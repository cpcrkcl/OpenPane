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

    private let fileBrowserService: any FileBrowserServicing
    private let workspaceService: any WorkspaceServicing

    init(
        currentURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileBrowserService: any FileBrowserServicing = FileBrowserService(),
        workspaceService: any WorkspaceServicing = WorkspaceService()
    ) {
        self.currentURL = currentURL
        self.items = []
        self.selectedItems = []
        self.isLoading = false
        self.errorMessage = nil
        self.includeHiddenFiles = false
        self.fileBrowserService = fileBrowserService
        self.workspaceService = workspaceService
    }

    func loadCurrentDirectory() async {
        isLoading = true
        errorMessage = nil
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

    func goUp() async {
        let parentURL = currentURL.deletingLastPathComponent()
        await setDirectory(parentURL)
    }

    func setDirectory(_ url: URL) async {
        currentURL = url
        selectedItems = []
        await loadCurrentDirectory()
    }

    private static func userReadableError(for error: Error, at url: URL) -> String {
        let directoryName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        return "Could not load \(directoryName): \(error.localizedDescription)"
    }
}
