//
//  FilePaneViewModelTests.swift
//  OpenPaneTests
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation
import Testing
@testable import OpenPane

@MainActor
struct FilePaneViewModelTests {
    @Test func defaultsToHomeDirectory() {
        let viewModel = FilePaneViewModel(fileBrowserService: MockFileBrowserService())

        #expect(viewModel.currentURL == FileManager.default.homeDirectoryForCurrentUser)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.selectedItems.isEmpty)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.includeHiddenFiles == false)
        #expect(viewModel.searchText == "")
        #expect(viewModel.filteredItems.isEmpty)
    }

    @Test func loadCurrentDirectoryLoadsItems() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let fileItem = try temporaryDirectory.createFileItem(named: "notes.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [fileItem]
            ])
        )

        await viewModel.loadCurrentDirectory()

        #expect(viewModel.items == [fileItem])
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func filteredItemsReturnsAllItemsWhenSearchTextIsEmpty() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let notesItem = try temporaryDirectory.createFileItem(named: "Notes.txt")
        let imageItem = try temporaryDirectory.createFileItem(named: "Image.png")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [notesItem, imageItem]
            ])
        )

        await viewModel.loadCurrentDirectory()

        #expect(viewModel.filteredItems == [notesItem, imageItem])
    }

    @Test func filteredItemsMatchesNamesCaseInsensitively() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let notesItem = try temporaryDirectory.createFileItem(named: "Meeting Notes.txt")
        let imageItem = try temporaryDirectory.createFileItem(named: "Image.png")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [notesItem, imageItem]
            ])
        )

        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "notes"

        #expect(viewModel.filteredItems == [notesItem])
    }

    @Test func filteredItemsTreatsWhitespaceOnlySearchAsEmpty() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let notesItem = try temporaryDirectory.createFileItem(named: "Notes.txt")
        let imageItem = try temporaryDirectory.createFileItem(named: "Image.png")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [notesItem, imageItem]
            ])
        )

        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "   "

        #expect(viewModel.filteredItems == [notesItem, imageItem])
    }

    @Test func setDirectoryClearsSelectionAndLoadsNewItems() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let directoryItem = try temporaryDirectory.createDirectoryItem(named: "Projects")
        let childItem = try temporaryDirectory.createFileItem(named: "Projects/readme.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [directoryItem],
                directoryItem.url: [childItem]
            ])
        )
        viewModel.selectedItems = [directoryItem]

        await viewModel.setDirectory(directoryItem.url)

        #expect(viewModel.currentURL == directoryItem.url)
        #expect(viewModel.selectedItems.isEmpty)
        #expect(viewModel.items == [childItem])
    }

    @Test func openDirectoryNavigatesIntoDirectory() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let directoryItem = try temporaryDirectory.createDirectoryItem(named: "Documents")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                directoryItem.url: []
            ])
        )

        await viewModel.open(directoryItem)

        #expect(viewModel.currentURL == directoryItem.url)
        #expect(viewModel.selectedItems.isEmpty)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func openSelectedItemShowsErrorWhenNothingIsSelected() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let workspaceService = MockWorkspaceService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            workspaceService: workspaceService
        )

        await viewModel.openSelectedItem()

        #expect(viewModel.errorMessage == "Select one item to open.")
        #expect(workspaceService.openedURLs.isEmpty)
    }

    @Test func openSelectedItemShowsErrorWhenMultipleItemsAreSelected() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createFileItem(named: "first.txt")
        let secondItem = try temporaryDirectory.createFileItem(named: "second.txt")
        let workspaceService = MockWorkspaceService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            workspaceService: workspaceService
        )
        viewModel.selectedItems = [firstItem, secondItem]

        await viewModel.openSelectedItem()

        #expect(viewModel.errorMessage == "Select only one item to open.")
        #expect(workspaceService.openedURLs.isEmpty)
    }

    @Test func openSelectedItemNavigatesIntoSelectedDirectory() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let directoryItem = try temporaryDirectory.createDirectoryItem(named: "Documents")
        let childItem = try temporaryDirectory.createFileItem(named: "Documents/notes.txt")
        let workspaceService = MockWorkspaceService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                directoryItem.url: [childItem]
            ]),
            workspaceService: workspaceService
        )
        viewModel.selectedItems = [directoryItem]

        await viewModel.openSelectedItem()

        #expect(viewModel.currentURL == directoryItem.url)
        #expect(viewModel.items == [childItem])
        #expect(viewModel.selectedItems.isEmpty)
        #expect(workspaceService.openedURLs.isEmpty)
    }

    @Test func openSelectedItemOpensSelectedFileWithWorkspaceService() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let fileItem = try temporaryDirectory.createFileItem(named: "notes.txt")
        let workspaceService = MockWorkspaceService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            workspaceService: workspaceService
        )
        viewModel.selectedItems = [fileItem]

        await viewModel.openSelectedItem()

        #expect(workspaceService.openedURLs == [fileItem.url])
        #expect(viewModel.errorMessage == nil)
    }

    @Test func revealSelectedItemsInFinderShowsErrorWhenNothingIsSelected() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let workspaceService = MockWorkspaceService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            workspaceService: workspaceService
        )

        viewModel.revealSelectedItemsInFinder()

        #expect(viewModel.errorMessage == "Select one or more items to reveal in Finder.")
        #expect(workspaceService.revealedURLs.isEmpty)
    }

    @Test func revealSelectedItemsInFinderRevealsOneOrMoreItems() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createFileItem(named: "first.txt")
        let secondItem = try temporaryDirectory.createFileItem(named: "second.txt")
        let workspaceService = MockWorkspaceService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            workspaceService: workspaceService
        )
        viewModel.selectedItems = [firstItem, secondItem]

        viewModel.revealSelectedItemsInFinder()

        #expect(Set(workspaceService.revealedURLs) == Set([firstItem.url, secondItem.url]))
        #expect(viewModel.errorMessage == nil)
    }

    @Test func goUpNavigatesToParentDirectory() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let viewModel = FilePaneViewModel(
            currentURL: childDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: []
            ])
        )

        await viewModel.goUp()

        #expect(viewModel.currentURL == temporaryDirectory.url)
        #expect(viewModel.selectedItems.isEmpty)
    }

    @Test func loadCurrentDirectoryStoresUserReadableError() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(errorURLs: [temporaryDirectory.url])
        )

        await viewModel.loadCurrentDirectory()

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage?.contains("Could not load") == true)
    }
}

@MainActor
private final class MockWorkspaceService: WorkspaceServicing, @unchecked Sendable {
    private(set) var openedURLs: [URL] = []
    private(set) var revealedURLs: [URL] = []

    func open(url: URL) {
        openedURLs.append(url)
    }

    func revealInFinder(urls: [URL]) {
        revealedURLs.append(contentsOf: urls)
    }
}

nonisolated private struct MockFileBrowserService: FileBrowserServicing {
    var itemsByURL: [URL: [FileItem]] = [:]
    var errorURLs: Set<URL> = []

    nonisolated func contentsOfDirectory(at url: URL, includeHiddenFiles: Bool) async throws -> [FileItem] {
        if errorURLs.contains(url) {
            throw CocoaError(.fileReadNoSuchFile)
        }

        return itemsByURL[url] ?? []
    }
}

private struct PaneTestTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPanePaneViewModelTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createDirectoryItem(named relativePath: String) throws -> FileItem {
        let directoryURL = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return try FileItem(url: directoryURL)
    }

    func createFileItem(named relativePath: String) throws -> FileItem {
        let fileURL = url.appendingPathComponent(relativePath)
        let parentURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let didCreateFile = FileManager.default.createFile(atPath: fileURL.path, contents: Data(relativePath.utf8))
        #expect(didCreateFile)

        return try FileItem(url: fileURL)
    }
}
