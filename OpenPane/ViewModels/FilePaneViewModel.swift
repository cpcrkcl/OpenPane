//
//  FilePaneViewModel.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import AppKit
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

    init(
        currentURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileBrowserService: any FileBrowserServicing = FileBrowserService()
    ) {
        self.currentURL = currentURL
        self.items = []
        self.selectedItems = []
        self.isLoading = false
        self.errorMessage = nil
        self.includeHiddenFiles = false
        self.fileBrowserService = fileBrowserService
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

        if !NSWorkspace.shared.open(item.url) {
            errorMessage = "Could not open \(item.displayName)."
        }
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
