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
    @Test func directoryNavigationAlsoEnrichesLightweightRowsAfterFirstPublish() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let fullItem = try temporaryDirectory.createFileItem(
            named: "Child/navigated.txt",
            contents: "metadata"
        )
        let lightweightItem = try FileItem(essentialURL: fullItem.url)
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                childDirectory.url: [lightweightItem]
            ]),
            metadataEnricher: { items in
                try await Task.sleep(nanoseconds: 50_000_000)
                return try await FilePaneViewModel.enrichMetadata(in: items)
            }
        )

        await viewModel.setDirectory(childDirectory.url)

        #expect(viewModel.items == [lightweightItem])
        #expect(viewModel.items.first?.hasExtendedMetadata == false)
        await viewModel.waitForMetadataEnrichment()
        #expect(viewModel.items.first?.hasExtendedMetadata == true)
    }

    @Test func directoryLoadPublishesLightweightRowsBeforeMetadataEnrichment() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let fullItem = try temporaryDirectory.createFileItem(named: "progressive.txt", contents: "metadata")
        let lightweightItem = try FileItem(essentialURL: fullItem.url)
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [temporaryDirectory.url: [lightweightItem]]),
            metadataEnricher: { items in
                try await Task.sleep(nanoseconds: 50_000_000)
                return try await FilePaneViewModel.enrichMetadata(in: items)
            }
        )

        await viewModel.loadCurrentDirectory()

        #expect(viewModel.items == [lightweightItem])
        #expect(viewModel.visibleItems == [lightweightItem])
        #expect(viewModel.items[0].hasExtendedMetadata == false)
        #expect(viewModel.isLoading == false)

        viewModel.selectFileListItem(lightweightItem, commandModifier: false, shiftModifier: false)
        let focusedID = viewModel.focusedFileListItemID
        await viewModel.waitForMetadataEnrichment()

        #expect(viewModel.items[0].hasExtendedMetadata)
        #expect(viewModel.items[0].size == fullItem.size)
        #expect(viewModel.selectedItems.map(\.id) == [fullItem.id])
        #expect(viewModel.focusedFileListItemID == focusedID)
        #expect(viewModel.metadataEnrichmentPublicationCount == 1)
    }

    @Test func defaultsToHomeDirectory() {
        let viewModel = FilePaneViewModel(fileBrowserService: MockFileBrowserService())

        #expect(viewModel.currentURL == FileManager.default.homeDirectoryForCurrentUser)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.selectedItems.isEmpty)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.includeHiddenFiles == false)
        #expect(viewModel.searchText == "")
        #expect(viewModel.tabs.count == 1)
        #expect(viewModel.tabs.first?.currentURL == viewModel.currentURL)
        #expect(viewModel.activeTabID == viewModel.tabs.first?.id)
        #expect(viewModel.recursiveSearchResults.isEmpty)
        #expect(viewModel.isShowingRecursiveSearchResults == false)
        #expect(viewModel.filteredItems.isEmpty)
        #expect(viewModel.backStack.isEmpty)
        #expect(viewModel.forwardStack.isEmpty)
        #expect(!viewModel.canGoBack)
        #expect(!viewModel.canGoForward)
    }

    @Test func newTabCreatesTabAtCurrentDirectory() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let fileItem = try temporaryDirectory.createFileItem(named: "notes.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [fileItem]
            ])
        )

        await viewModel.newTab()

        #expect(viewModel.tabs.count == 2)
        #expect(viewModel.currentURL == temporaryDirectory.url)
        #expect(viewModel.items == [fileItem])
        #expect(viewModel.selectedItems.isEmpty)
        #expect(viewModel.tabs.last?.id == viewModel.activeTabID)
    }

    @Test func switchToTabPreservesCurrentURLItemsAndSelectionPerTab() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let rootItem = try temporaryDirectory.createFileItem(named: "root.txt")
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let childItem = try temporaryDirectory.createFileItem(named: "Child/child.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [rootItem, childDirectory],
                childDirectory.url: [childItem]
            ])
        )

        await viewModel.loadCurrentDirectory()
        viewModel.selectedItems = [rootItem]
        let firstTabID = viewModel.activeTabID

        await viewModel.newTab()
        let secondTabID = viewModel.activeTabID
        await viewModel.setDirectory(childDirectory.url)
        viewModel.selectedItems = [childItem]

        await viewModel.switchToTab(firstTabID)

        #expect(viewModel.currentURL == temporaryDirectory.url)
        #expect(viewModel.items == [rootItem, childDirectory])
        #expect(viewModel.selectedItems == [rootItem])

        await viewModel.switchToTab(secondTabID)

        #expect(viewModel.currentURL == childDirectory.url)
        #expect(viewModel.items == [childItem])
        #expect(viewModel.selectedItems == [childItem])
    }

    @Test func dirtyBackgroundTabReloadsWhenActivatedAndClearsDirtyFlag() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let rootItem = try temporaryDirectory.createFileItem(named: "root.txt")
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let staleChildItem = try temporaryDirectory.createFileItem(named: "Child/stale.txt")
        let freshChildItem = try temporaryDirectory.createFileItem(named: "Child/fresh.txt")
        let fileBrowserService = MutableMockFileBrowserService(itemsByURL: [
            temporaryDirectory.url: [rootItem, childDirectory],
            childDirectory.url: [staleChildItem]
        ])
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: fileBrowserService
        )
        await viewModel.loadCurrentDirectory()
        let rootTabID = viewModel.activeTabID
        await viewModel.newTab()
        await viewModel.setDirectory(childDirectory.url)
        let childTabID = viewModel.activeTabID
        await viewModel.switchToTab(rootTabID)
        fileBrowserService.setItems([freshChildItem], for: childDirectory.url)

        viewModel.markTabsDirty(showingAnyOf: [childDirectory.url])
        await viewModel.switchToTab(childTabID)

        #expect(viewModel.items == [freshChildItem])
        #expect(viewModel.tabs.first { $0.id == childTabID }?.isDirty == false)
        #expect(fileBrowserService.loadCount(for: childDirectory.url) == 2)
    }

    @Test func cleanBackgroundTabUsesCachedContentsWhenActivated() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let rootItem = try temporaryDirectory.createFileItem(named: "root.txt")
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let staleChildItem = try temporaryDirectory.createFileItem(named: "Child/stale.txt")
        let freshChildItem = try temporaryDirectory.createFileItem(named: "Child/fresh.txt")
        let fileBrowserService = MutableMockFileBrowserService(itemsByURL: [
            temporaryDirectory.url: [rootItem, childDirectory],
            childDirectory.url: [staleChildItem]
        ])
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: fileBrowserService
        )
        await viewModel.loadCurrentDirectory()
        let rootTabID = viewModel.activeTabID
        await viewModel.newTab()
        await viewModel.setDirectory(childDirectory.url)
        let childTabID = viewModel.activeTabID
        await viewModel.switchToTab(rootTabID)
        fileBrowserService.setItems([freshChildItem], for: childDirectory.url)

        await viewModel.switchToTab(childTabID)

        #expect(viewModel.items == [staleChildItem])
        #expect(fileBrowserService.loadCount(for: childDirectory.url) == 1)
    }

    @Test func failedDirtyTabReloadKeepsTabDirty() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let rootItem = try temporaryDirectory.createFileItem(named: "root.txt")
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let staleChildItem = try temporaryDirectory.createFileItem(named: "Child/stale.txt")
        let fileBrowserService = MutableMockFileBrowserService(itemsByURL: [
            temporaryDirectory.url: [rootItem, childDirectory],
            childDirectory.url: [staleChildItem]
        ])
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: fileBrowserService
        )
        await viewModel.loadCurrentDirectory()
        let rootTabID = viewModel.activeTabID
        await viewModel.newTab()
        await viewModel.setDirectory(childDirectory.url)
        let childTabID = viewModel.activeTabID
        await viewModel.switchToTab(rootTabID)
        fileBrowserService.setError(FileBrowserError.directoryNotFound(childDirectory.url), for: childDirectory.url)

        viewModel.markTabsDirty(showingAnyOf: [childDirectory.url])
        await viewModel.switchToTab(childTabID)

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.tabs.first { $0.id == childTabID }?.isDirty == true)
        #expect(viewModel.errorMessage == "Child could not be found.")
    }

    @Test func closeActiveTabSwitchesToRemainingTab() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let fileItem = try temporaryDirectory.createFileItem(named: "notes.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [fileItem]
            ])
        )
        let firstTabID = viewModel.activeTabID
        await viewModel.newTab()
        let secondTabID = viewModel.activeTabID

        await viewModel.closeTab(secondTabID)

        #expect(viewModel.tabs.count == 1)
        #expect(viewModel.activeTabID == firstTabID)
        #expect(viewModel.currentURL == temporaryDirectory.url)
    }

    @Test func closeOnlyTabDoesNothing() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService()
        )
        let tabID = viewModel.activeTabID

        await viewModel.closeTab(tabID)

        #expect(viewModel.tabs.count == 1)
        #expect(viewModel.activeTabID == tabID)
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

    @Test func staleLoadResultIsDiscardedAfterTabSwitch() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let rootItem = try temporaryDirectory.createFileItem(named: "root.txt")
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let childItem = try temporaryDirectory.createFileItem(named: "Child/child.txt")
        let fileBrowserService = DelayedMockFileBrowserService(
            itemsByURL: [
                temporaryDirectory.url: [rootItem],
                childDirectory.url: [childItem]
            ],
            delayNanosecondsByURL: [
                temporaryDirectory.url: 80_000_000
            ]
        )
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: fileBrowserService
        )

        let loadTask = Task {
            await viewModel.loadCurrentDirectory()
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.receiveTab(FilePaneTab(currentURL: childDirectory.url, items: [childItem]))

        await loadTask.value

        #expect(viewModel.currentURL == childDirectory.url)
        #expect(viewModel.items == [childItem])
        #expect(viewModel.errorMessage == nil)
    }

    @Test func staleLoadErrorIsDiscardedAfterTabSwitch() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let childItem = try temporaryDirectory.createFileItem(named: "Child/child.txt")
        let fileBrowserService = DelayedMockFileBrowserService(
            errorByURL: [
                temporaryDirectory.url: FileBrowserError.directoryNotFound(temporaryDirectory.url)
            ],
            delayNanosecondsByURL: [
                temporaryDirectory.url: 80_000_000
            ]
        )
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: fileBrowserService
        )

        let loadTask = Task {
            await viewModel.loadCurrentDirectory()
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.receiveTab(FilePaneTab(currentURL: childDirectory.url, items: [childItem]))

        await loadTask.value

        #expect(viewModel.currentURL == childDirectory.url)
        #expect(viewModel.items == [childItem])
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

        #expect(viewModel.filteredItems == [imageItem, notesItem])
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
        await viewModel.waitForVisibleItemsUpdate()

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
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.filteredItems == [imageItem, notesItem])
    }

    @Test func filteredItemsSortsByNameAcrossFilesAndDirectories() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let zebraItem = try temporaryDirectory.createDirectoryItem(named: "Zebra")
        let alphaItem = try temporaryDirectory.createFileItem(named: "Alpha.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [zebraItem, alphaItem]
            ])
        )

        await viewModel.loadCurrentDirectory()

        #expect(viewModel.filteredItems == [alphaItem, zebraItem])
    }

    @Test func filteredItemsCanSortBySize() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let largeItem = try temporaryDirectory.createFileItem(named: "large.txt", contents: "larger contents")
        let smallItem = try temporaryDirectory.createFileItem(named: "small.txt", contents: "s")
        let directoryItem = try temporaryDirectory.createDirectoryItem(named: "Folder")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [largeItem, smallItem, directoryItem]
            ])
        )

        await viewModel.loadCurrentDirectory()
        viewModel.sortOption = .size
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.filteredItems == [directoryItem, smallItem, largeItem])
    }

    @Test func headerSortTogglesNameDirectionAcrossFilesAndDirectories() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let bravoFolder = try temporaryDirectory.createDirectoryItem(named: "Bravo")
        let alphaFile = try temporaryDirectory.createFileItem(named: "Alpha.txt")
        let deltaFolder = try temporaryDirectory.createDirectoryItem(named: "Delta")
        let charlieFile = try temporaryDirectory.createFileItem(named: "Charlie.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [bravoFolder, alphaFile, deltaFolder, charlieFile]
            ])
        )

        await viewModel.loadCurrentDirectory()
        #expect(viewModel.filteredItems == [alphaFile, bravoFolder, charlieFile, deltaFolder])

        viewModel.applyHeaderSort(.name)
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.filteredItems == [deltaFolder, charlieFile, bravoFolder, alphaFile])
    }

    @Test func visibleItemsUpdatesWhenSearchTextChanges() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let notesItem = try temporaryDirectory.createFileItem(named: "Project Notes.txt")
        let imageItem = try temporaryDirectory.createFileItem(named: "Image.png")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [notesItem, imageItem]
            ])
        )

        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "notes"
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.visibleItems == [notesItem])
    }

    @Test func searchTextAssignmentDoesNotSynchronouslyFilterOrSort() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let alphaItem = try temporaryDirectory.createFileItem(named: "Alpha.txt")
        let betaItem = try temporaryDirectory.createFileItem(named: "Beta.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [alphaItem, betaItem]
            ]),
            visibleItemsSearchDebounceNanoseconds: 20_000_000
        )
        await viewModel.loadCurrentDirectory()
        let recomputeCount = viewModel.visibleItemsRecomputeCount

        viewModel.searchText = "beta"

        #expect(viewModel.visibleItems == [alphaItem, betaItem])
        #expect(viewModel.visibleItemsRecomputeCount == recomputeCount)

        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.visibleItems == [betaItem])
        #expect(viewModel.visibleItemsRecomputeCount == recomputeCount + 1)
    }

    @Test func rapidSearchChangesPublishOnlyLatestResult() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let alphaItem = try temporaryDirectory.createFileItem(named: "Alpha.txt")
        let betaItem = try temporaryDirectory.createFileItem(named: "Beta.txt")
        let gammaItem = try temporaryDirectory.createFileItem(named: "Gamma.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [alphaItem, betaItem, gammaItem]
            ]),
            visibleItemsSearchDebounceNanoseconds: 30_000_000
        )
        await viewModel.loadCurrentDirectory()
        let recomputeCount = viewModel.visibleItemsRecomputeCount

        viewModel.searchText = "alpha"
        try await Task.sleep(nanoseconds: 5_000_000)
        viewModel.searchText = "beta"
        try await Task.sleep(nanoseconds: 5_000_000)
        viewModel.searchText = "gamma"
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.visibleItems == [gammaItem])
        #expect(viewModel.visibleItemsRecomputeCount == recomputeCount + 1)
    }

    @Test func visibleItemsUpdatesWhenSortOptionChanges() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let largeItem = try temporaryDirectory.createFileItem(named: "large.txt", contents: "larger contents")
        let smallItem = try temporaryDirectory.createFileItem(named: "small.txt", contents: "s")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [largeItem, smallItem]
            ])
        )

        await viewModel.loadCurrentDirectory()
        viewModel.sortOption = .size
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.visibleItems == [smallItem, largeItem])
    }

    @Test func headerSortsByModifiedDateAcrossFilesAndDirectories() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let oldestFolder = try temporaryDirectory.createDirectoryItem(named: "Zulu Folder")
        let middleFile = try temporaryDirectory.createFileItem(named: "Alpha File.txt")
        let newestFolder = try temporaryDirectory.createDirectoryItem(named: "Beta Folder")
        let fileManager = FileManager.default
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: oldestFolder.url.path
        )
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000)],
            ofItemAtPath: middleFile.url.path
        )
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 3_000)],
            ofItemAtPath: newestFolder.url.path
        )
        let datedOldestFolder = try FileItem(url: oldestFolder.url)
        let datedMiddleFile = try FileItem(url: middleFile.url)
        let datedNewestFolder = try FileItem(url: newestFolder.url)
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [datedNewestFolder, datedOldestFolder, datedMiddleFile]
            ])
        )

        await viewModel.loadCurrentDirectory()
        viewModel.applyHeaderSort(.modifiedDate)
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.visibleItems == [datedOldestFolder, datedMiddleFile, datedNewestFolder])

        viewModel.applyHeaderSort(.modifiedDate)
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.visibleItems == [datedNewestFolder, datedMiddleFile, datedOldestFolder])
    }

    @Test func visibleItemsUpdatesWhenSortDirectionChanges() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let alphaItem = try temporaryDirectory.createFileItem(named: "Alpha.txt")
        let betaItem = try temporaryDirectory.createFileItem(named: "Beta.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [alphaItem, betaItem]
            ])
        )

        await viewModel.loadCurrentDirectory()
        viewModel.sortDirection = .descending
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.visibleItems == [betaItem, alphaItem])
    }

    @Test func sortChangeAfterItemReplacementDoesNotReuseStaleRows() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let staleItem = try temporaryDirectory.createFileItem(named: "Stale.txt")
        let replacementItem = try temporaryDirectory.createFileItem(named: "Replacement.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService()
        )
        viewModel.items = [staleItem]
        await viewModel.waitForVisibleItemsUpdate()

        // Both mutations happen on the main actor without yielding. The
        // replacement computation is therefore cancelled by the sort change.
        viewModel.items = [replacementItem]
        viewModel.sortOption = .size
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.visibleItems == [replacementItem])
    }

    @Test func visibleItemsUpdatesWhenRecursiveSearchResultsBecomeActive() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let localItem = try temporaryDirectory.createFileItem(named: "Local.txt")
        let searchResult = try temporaryDirectory.createFileItem(named: "Nested/Result.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [localItem]
            ])
        )

        await viewModel.loadCurrentDirectory()
        viewModel.recursiveSearchResults = [searchResult]
        viewModel.isShowingRecursiveSearchResults = true
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.visibleItems == [searchResult])
    }

    @Test func selectionChangesDoNotRecomputeVisibleItems() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createFileItem(named: "Alpha.txt")
        let secondItem = try temporaryDirectory.createFileItem(named: "Beta.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [firstItem, secondItem]
            ])
        )

        await viewModel.loadCurrentDirectory()
        let recomputeCount = viewModel.visibleItemsRecomputeCount

        viewModel.selectedItems = [secondItem]

        #expect(viewModel.visibleItems == [firstItem, secondItem])
        #expect(viewModel.visibleItemsRecomputeCount == recomputeCount)
    }

    @Test func selectionChangesDoNotRepublishTabsArray() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let item = try temporaryDirectory.createFileItem(named: "Selected.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [temporaryDirectory.url: [item]])
        )
        await viewModel.loadCurrentDirectory()
        let publicationCount = viewModel.tabsPublicationCount

        viewModel.selectedItems = [item]

        #expect(viewModel.tabsPublicationCount == publicationCount)
    }

    @Test func backgroundTabItemCachesAreBounded() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService()
        )

        for index in 0..<8 {
            let item = try temporaryDirectory.createFileItem(named: "tab-\(index).txt")
            viewModel.receiveTab(
                FilePaneTab(
                    currentURL: temporaryDirectory.url.appendingPathComponent("tab-\(index)", isDirectory: true),
                    items: [item]
                )
            )
        }

        let cachedBackgroundTabs = viewModel.tabs.filter {
            $0.id != viewModel.activeTabID && !$0.items.isEmpty
        }
        #expect(cachedBackgroundTabs.count <= 4)
        #expect(viewModel.tabs.filter(\.isDirty).count >= 3)
    }

    @Test func itemsForDragReturnsSelectedItemsWhenStartingItemIsSelected() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createFileItem(named: "Alpha.txt")
        let secondItem = try temporaryDirectory.createFileItem(named: "Beta.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService()
        )
        viewModel.selectedItems = [secondItem, firstItem]

        let dragItems = viewModel.itemsForDrag(startingFrom: secondItem)

        #expect(dragItems == [firstItem, secondItem])
        #expect(viewModel.selectedItems == [firstItem, secondItem])
    }

    @Test func itemsForDragSelectsOnlyStartingItemWhenItIsNotSelected() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createFileItem(named: "Alpha.txt")
        let secondItem = try temporaryDirectory.createFileItem(named: "Beta.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService()
        )
        viewModel.selectedItems = [firstItem]

        let dragItems = viewModel.itemsForDrag(startingFrom: secondItem)

        #expect(dragItems == [secondItem])
        #expect(viewModel.selectedItems == [secondItem])
    }

    @Test func fileDragPayloadEncodesSourcePaneAndFileURLs() throws {
        let fileURLs = [
            URL(filePath: "/tmp/Alpha.txt"),
            URL(filePath: "/tmp/Beta.txt")
        ]
        let payload = FileDragPayload(sourcePaneSide: .left, fileURLs: fileURLs)

        let data = try #require(payload.encodedData)
        let decodedPayload = try #require(FileDragPayload.decoded(from: data))

        #expect(decodedPayload.sourcePaneSide == .left)
        #expect(decodedPayload.fileURLs == fileURLs)
    }

    @Test func performRecursiveSearchShowsRecursiveResults() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let searchResult = try temporaryDirectory.createFileItem(named: "Nested/Notes.txt")
        let localItem = try temporaryDirectory.createFileItem(named: "Local.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [localItem]
            ]),
            fileSearchService: MockFileSearchService(results: [searchResult])
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "notes"

        await viewModel.performRecursiveSearch()

        #expect(viewModel.items == [localItem])
        #expect(viewModel.recursiveSearchResults == [searchResult])
        #expect(viewModel.filteredItems == [searchResult])
        #expect(viewModel.isShowingRecursiveSearchResults)
        #expect(viewModel.isSearchingSubtree == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func contentsSearchStoresAnnotationsAndSkippedFileStatus() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let searchResult = try temporaryDirectory.createFileItem(named: "Nested/Notes.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            fileSearchService: ContentSearchMockFileSearchService(
                response: FileSearchResponse(
                    results: [
                        FileSearchResult(
                            item: searchResult,
                            contentMatch: FileContentMatch(
                                lineNumber: 7,
                                excerpt: "Needle in the notes"
                            )
                        )
                    ],
                    skippedFileCount: 2
                )
            )
        )
        viewModel.searchMode = .contents
        viewModel.searchText = "needle"

        await viewModel.performRecursiveSearch()

        #expect(viewModel.recursiveSearchResults == [searchResult])
        #expect(viewModel.recursiveSearchContentMatch(for: searchResult)?.lineNumber == 7)
        #expect(
            viewModel.recursiveSearchContentDescription(for: searchResult) ==
                "Nested/Notes.txt • Line 7: Needle in the notes"
        )
        #expect(viewModel.searchStatusText == "1 result • 2 files skipped")
    }

    @Test func clearRecursiveSearchReturnsToCurrentFolderFilter() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let searchResult = try temporaryDirectory.createFileItem(named: "Nested/Notes.txt")
        let localItem = try temporaryDirectory.createFileItem(named: "Local Notes.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [localItem]
            ]),
            fileSearchService: MockFileSearchService(results: [searchResult])
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "notes"
        await viewModel.performRecursiveSearch()

        viewModel.clearRecursiveSearch()
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.recursiveSearchResults.isEmpty)
        #expect(viewModel.isShowingRecursiveSearchResults == false)
        #expect(viewModel.filteredItems == [localItem])
    }

    @Test func switchingFromSubtreeSearchToFilterRestoresLiveFolderFiltering() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let searchResult = try temporaryDirectory.createFileItem(named: "Nested/Notes.txt")
        let matchingLocalItem = try temporaryDirectory.createFileItem(named: "Local Notes.txt")
        let otherLocalItem = try temporaryDirectory.createFileItem(named: "Photo.jpg")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [matchingLocalItem, otherLocalItem]
            ]),
            fileSearchService: MockFileSearchService(results: [searchResult])
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "notes"
        await viewModel.triggerSubtreeSearch()

        viewModel.searchMode = .filter
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.isShowingRecursiveSearchResults == false)
        #expect(viewModel.visibleItems == [matchingLocalItem])
    }

    @Test func subtreeModeDoesNotApplyTheCurrentFolderFilterBeforeSubmission() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let matchingItem = try temporaryDirectory.createFileItem(named: "Notes.txt")
        let otherItem = try temporaryDirectory.createFileItem(named: "Photo.jpg")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [matchingItem, otherItem]
            ])
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchMode = .subtree
        viewModel.searchText = "notes"

        await viewModel.waitForVisibleItemsUpdate()

        #expect(Set(viewModel.visibleItems) == Set([matchingItem, otherItem]))
        #expect(viewModel.isShowingRecursiveSearchResults == false)
    }

    @Test func editingQueryClearsCompletedSubtreeResults() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let localItem = try temporaryDirectory.createFileItem(named: "Local.txt")
        let searchResult = try temporaryDirectory.createFileItem(named: "Nested/Notes.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [localItem]
            ]),
            fileSearchService: MockFileSearchService(results: [searchResult])
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "notes"
        await viewModel.triggerSubtreeSearch()

        viewModel.searchText = "photos"
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.recursiveSearchResults.isEmpty)
        #expect(viewModel.isShowingRecursiveSearchResults == false)
        #expect(viewModel.visibleItems == [localItem])
    }

    @Test func switchingToFilterCancelsInFlightSubtreeSearch() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let localItem = try temporaryDirectory.createFileItem(named: "Local Notes.txt")
        let searchResult = try temporaryDirectory.createFileItem(named: "Nested/Notes.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [localItem]
            ]),
            fileSearchService: DelayedMockFileSearchService(
                results: [searchResult],
                delayNanoseconds: 100_000_000
            )
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "notes"
        let searchTask = Task {
            await viewModel.triggerSubtreeSearch()
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        viewModel.searchMode = .filter
        await searchTask.value
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.isSearchingSubtree == false)
        #expect(viewModel.isShowingRecursiveSearchResults == false)
        #expect(viewModel.visibleItems == [localItem])
    }

    @Test func switchingSearchKindsCancelsResultsFromThePreviousKind() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let localItem = try temporaryDirectory.createFileItem(named: "Local.txt")
        let staleNameResult = try temporaryDirectory.createFileItem(named: "Nested/Needle.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [localItem]
            ]),
            fileSearchService: DelayedMockFileSearchService(
                results: [staleNameResult],
                delayNanoseconds: 100_000_000
            )
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchMode = .names
        viewModel.searchText = "needle"
        let searchTask = Task {
            await viewModel.performRecursiveSearch()
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        viewModel.searchMode = .contents
        await searchTask.value
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.searchMode == .contents)
        #expect(viewModel.isSearchingSubtree == false)
        #expect(viewModel.isShowingRecursiveSearchResults == false)
        #expect(viewModel.recursiveSearchResults.isEmpty)
        #expect(viewModel.recursiveSearchContentMatches.isEmpty)
        #expect(viewModel.visibleItems == [localItem])
    }

    @Test func staleRecursiveSearchResultIsDiscardedAfterClearingSearch() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let searchResult = try temporaryDirectory.createFileItem(named: "Nested/Notes.txt")
        let localItem = try temporaryDirectory.createFileItem(named: "Local Notes.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [localItem]
            ]),
            fileSearchService: DelayedMockFileSearchService(
                results: [searchResult],
                delayNanoseconds: 50_000_000
            )
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "notes"

        let searchTask = Task {
            await viewModel.performRecursiveSearch()
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.clearRecursiveSearch()
        await searchTask.value
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.recursiveSearchResults.isEmpty)
        #expect(viewModel.isShowingRecursiveSearchResults == false)
        #expect(viewModel.filteredItems == [localItem])
    }

    @Test func performRecursiveSearchShowsErrorForEmptyQuery() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            fileSearchService: MockFileSearchService()
        )
        viewModel.searchText = "   "

        await viewModel.performRecursiveSearch()

        #expect(viewModel.errorMessage == "Enter a search term.")
        #expect(viewModel.isShowingRecursiveSearchResults == false)
        #expect(viewModel.isSearchingSubtree == false)
    }

    @Test func performRecursiveSearchQueuesUntilNavigationCompletes() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let searchResult = try temporaryDirectory.createFileItem(named: "Nested/Notes.txt")
        let slowBrowser = DelayedMockFileBrowserService(
            itemsByURL: [
                temporaryDirectory.url: [childDirectory],
                childDirectory.url: []
            ],
            delayNanosecondsByURL: [childDirectory.url: 100_000_000]
        )
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: slowBrowser,
            fileSearchService: MockFileSearchService(results: [searchResult])
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "notes"

        let navigationTask = Task {
            await viewModel.setDirectory(childDirectory.url)
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        let searchTask = Task {
            await viewModel.performRecursiveSearch()
        }

        await Task.yield()
        #expect(viewModel.isSearchingSubtree)

        await navigationTask.value
        await searchTask.value
        await viewModel.waitForVisibleItemsUpdate()

        #expect(viewModel.isShowingRecursiveSearchResults)
        #expect(viewModel.recursiveSearchResults == [searchResult])
        #expect(viewModel.isSearchingSubtree == false)
    }

    @Test func multipleRecursiveSearchCallersRemainQueuedUntilNavigationCompletes() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let searchResult = try temporaryDirectory.createFileItem(named: "Child/Notes.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: DelayedMockFileBrowserService(
                itemsByURL: [childDirectory.url: []],
                delayNanosecondsByURL: [childDirectory.url: 100_000_000]
            ),
            fileSearchService: MockFileSearchService(results: [searchResult])
        )
        viewModel.searchText = "notes"

        let navigationTask = Task {
            await viewModel.setDirectory(childDirectory.url)
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        var firstSearchFinished = false
        var secondSearchFinished = false
        let firstSearchTask = Task {
            await viewModel.performRecursiveSearch()
            firstSearchFinished = true
        }
        await Task.yield()
        let secondSearchTask = Task {
            await viewModel.performRecursiveSearch()
            secondSearchFinished = true
        }
        await Task.yield()

        #expect(firstSearchFinished == false)
        #expect(secondSearchFinished == false)

        await navigationTask.value
        await firstSearchTask.value
        await secondSearchTask.value

        #expect(firstSearchFinished)
        #expect(secondSearchFinished)
        #expect(viewModel.recursiveSearchResults == [searchResult])
    }

    @Test func recursiveSearchDoesNotCancelInFlightMetadataEnrichment() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let fullItem = try temporaryDirectory.createFileItem(named: "Notes.txt", contents: "metadata")
        let lightweightItem = try FileItem(essentialURL: fullItem.url)
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [lightweightItem]
            ]),
            fileSearchService: MockFileSearchService(results: [fullItem]),
            metadataEnricher: { items in
                try await Task.sleep(nanoseconds: 50_000_000)
                return try await FilePaneViewModel.enrichMetadata(in: items)
            }
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "notes"

        await viewModel.performRecursiveSearch()
        await viewModel.waitForMetadataEnrichment()

        #expect(viewModel.items.first?.hasExtendedMetadata == true)
        #expect(viewModel.isShowingRecursiveSearchResults)
    }

    @Test func navigationCancelsAnInFlightSubtreeSearchWithoutLeavingTheSpinnerActive() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let searchResult = try temporaryDirectory.createFileItem(named: "Nested/Notes.txt")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [childDirectory],
                childDirectory.url: []
            ]),
            fileSearchService: DelayedMockFileSearchService(
                results: [searchResult],
                delayNanoseconds: 100_000_000
            )
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "notes"

        let searchTask = Task {
            await viewModel.performRecursiveSearch()
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        await viewModel.setDirectory(childDirectory.url)
        await searchTask.value

        #expect(viewModel.currentURL == childDirectory.url)
        #expect(viewModel.isSearchingSubtree == false)
        #expect(viewModel.isShowingRecursiveSearchResults == false)
    }

    @Test func clearingAFilterDoesNotCancelInFlightDirectoryNavigation() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let browser = DelayedMockFileBrowserService(
            itemsByURL: [
                temporaryDirectory.url: [childDirectory],
                childDirectory.url: []
            ],
            delayNanosecondsByURL: [childDirectory.url: 100_000_000]
        )
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: browser
        )
        await viewModel.loadCurrentDirectory()
        viewModel.searchText = "child"

        let navigationTask = Task {
            await viewModel.setDirectory(childDirectory.url)
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.clearSearch()
        await navigationTask.value

        #expect(viewModel.currentURL.standardizedFileURL == childDirectory.url.standardizedFileURL)
        #expect(viewModel.searchText.isEmpty)
    }

    @Test func navigateToPathExpandsTildeAndNavigates() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Projects")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [childDirectory],
                childDirectory.url: []
            ])
        )
        await viewModel.loadCurrentDirectory()

        let succeeded = await viewModel.navigateToPath(childDirectory.url.path)

        #expect(succeeded)
        #expect(viewModel.currentURL.standardizedFileURL == childDirectory.url.standardizedFileURL)
    }

    @Test func navigateToPathRejectsMissingDirectory() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService()
        )

        let succeeded = await viewModel.navigateToPath("/tmp/OpenPaneMissing-\(UUID().uuidString)")

        #expect(succeeded == false)
        #expect(viewModel.errorMessage?.contains("doesn’t exist") == true)
    }

    @Test func navigateToPathReportsFailureWhenDirectoryCannotBeLoaded() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Projects")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(errorByURL: [
                childDirectory.url: FileBrowserError.accessDenied(childDirectory.url)
            ])
        )

        let succeeded = await viewModel.navigateToPath(childDirectory.url.path)

        #expect(succeeded == false)
        #expect(viewModel.currentURL == temporaryDirectory.url)
        #expect(viewModel.errorMessage == "You do not have permission to open Projects.")
    }

    @Test func equivalentStandardizedPathRefreshesWithoutAddingHistoryEntry() async {
        let rootURL = URL(filePath: "/tmp/OpenPane/Folder", directoryHint: .isDirectory)
        let equivalentURL = rootURL.appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("Folder", isDirectory: true)
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: MockFileBrowserService()
        )

        await viewModel.setDirectory(equivalentURL)

        #expect(viewModel.currentURL == rootURL)
        #expect(viewModel.backStack.isEmpty)
    }

    @Test func navigateToPathRejectsRelativePaths() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService()
        )

        let succeeded = await viewModel.navigateToPath("relative/path")

        #expect(succeeded == false)
        #expect(viewModel.errorMessage == "Enter an absolute path or a path beginning with ~.")
    }

    @Test func navigateToPathCanLeaveTheNetworkPage() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Projects")
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [childDirectory.url: []])
        )
        await viewModel.navigate(to: .network)

        let succeeded = await viewModel.navigateToPath(childDirectory.url.path)

        #expect(succeeded)
        #expect(viewModel.currentLocation == .file(childDirectory.url.standardizedFileURL))
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

    @Test func navigatingToNewDirectoryPushesPreviousURLOntoBackStack() async {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let childURL = URL(filePath: "/root/child", directoryHint: .isDirectory)
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: MockFileBrowserService()
        )

        await viewModel.setDirectory(childURL)

        #expect(viewModel.currentURL == childURL)
        #expect(viewModel.backStack == [rootURL])
        #expect(viewModel.forwardStack.isEmpty)
        #expect(viewModel.canGoBack)
        #expect(!viewModel.canGoForward)
    }

    @Test func goBackMovesCurrentURLOntoForwardStack() async {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let childURL = URL(filePath: "/root/child", directoryHint: .isDirectory)
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: MockFileBrowserService()
        )
        await viewModel.setDirectory(childURL)

        await viewModel.goBack()

        #expect(viewModel.currentURL == rootURL)
        #expect(viewModel.backStack.isEmpty)
        #expect(viewModel.forwardStack == [childURL])
        #expect(!viewModel.canGoBack)
        #expect(viewModel.canGoForward)
    }

    @Test func goForwardMovesCurrentURLBackOntoBackStack() async {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let childURL = URL(filePath: "/root/child", directoryHint: .isDirectory)
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: MockFileBrowserService()
        )
        await viewModel.setDirectory(childURL)
        await viewModel.goBack()

        await viewModel.goForward()

        #expect(viewModel.currentURL == childURL)
        #expect(viewModel.backStack == [rootURL])
        #expect(viewModel.forwardStack.isEmpty)
    }

    @Test func navigatingAfterGoingBackClearsForwardStack() async {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let firstURL = URL(filePath: "/root/first", directoryHint: .isDirectory)
        let secondURL = URL(filePath: "/root/second", directoryHint: .isDirectory)
        let replacementURL = URL(filePath: "/root/replacement", directoryHint: .isDirectory)
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: MockFileBrowserService()
        )
        await viewModel.setDirectory(firstURL)
        await viewModel.setDirectory(secondURL)
        await viewModel.goBack()

        await viewModel.setDirectory(replacementURL)

        #expect(viewModel.currentURL == replacementURL)
        #expect(viewModel.backStack == [rootURL, firstURL])
        #expect(viewModel.forwardStack.isEmpty)
    }

    @Test func latestDirectoryRequestWinsWhileEarlierLoadIsSlow() async throws {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let slowURL = URL(filePath: "/root/slow", directoryHint: .isDirectory)
        let latestURL = URL(filePath: "/root/latest", directoryHint: .isDirectory)
        let latestItem = try PaneTestTemporaryDirectory().createFileItem(named: "latest.txt")
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: DelayedMockFileBrowserService(
                itemsByURL: [latestURL: [latestItem]],
                delayNanosecondsByURL: [slowURL: 300_000_000]
            )
        )

        let slowNavigation = Task { @MainActor in
            await viewModel.setDirectory(slowURL)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        await viewModel.setDirectory(latestURL)
        await slowNavigation.value

        #expect(viewModel.currentURL == latestURL)
        #expect(viewModel.items == [latestItem])
        #expect(viewModel.backStack == [rootURL])
        #expect(viewModel.forwardStack.isEmpty)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func backNavigationCancelsPendingFolderLoadAndWins() async throws {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let currentURL = URL(filePath: "/root/current", directoryHint: .isDirectory)
        let slowURL = URL(filePath: "/root/current/slow", directoryHint: .isDirectory)
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: DelayedMockFileBrowserService(
                delayNanosecondsByURL: [slowURL: 300_000_000]
            )
        )
        await viewModel.setDirectory(currentURL)

        let slowNavigation = Task { @MainActor in
            await viewModel.setDirectory(slowURL)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        await viewModel.goBack()
        await slowNavigation.value

        #expect(viewModel.currentURL == rootURL)
        #expect(viewModel.backStack.isEmpty)
        #expect(viewModel.forwardStack == [currentURL])
        #expect(viewModel.isLoading == false)
    }

    @Test func latestNavigationFailureIsReportedAndStaleSuccessIsDiscarded() async throws {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let slowURL = URL(filePath: "/root/slow", directoryHint: .isDirectory)
        let missingURL = URL(filePath: "/root/missing", directoryHint: .isDirectory)
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: DelayedMockFileBrowserService(
                errorByURL: [missingURL: FileBrowserError.directoryNotFound(missingURL)],
                delayNanosecondsByURL: [slowURL: 300_000_000]
            )
        )

        let slowNavigation = Task { @MainActor in
            await viewModel.setDirectory(slowURL)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        await viewModel.setDirectory(missingURL)
        await slowNavigation.value

        #expect(viewModel.currentURL == rootURL)
        #expect(viewModel.backStack.isEmpty)
        #expect(viewModel.errorMessage == "missing could not be found.")
        #expect(viewModel.isLoading == false)
    }

    @Test func monitorRefreshInFlightCannotBlockSubsequentUserNavigation() async throws {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let childURL = URL(filePath: "/root/child", directoryHint: .isDirectory)
        let childItem = try PaneTestTemporaryDirectory().createFileItem(named: "child.txt")
        let fileBrowserService = MutableMockFileBrowserService(
            itemsByURL: [childURL: [childItem]],
            delayNanosecondsByURL: [rootURL: 300_000_000]
        )
        let directoryMonitorService = MockDirectoryMonitorService()
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: fileBrowserService,
            directoryMonitorService: directoryMonitorService,
            directoryRefreshDebounceNanoseconds: 1_000_000
        )

        directoryMonitorService.emitChange(for: rootURL)
        let monitorLoadStarted = try await waitUntil {
            fileBrowserService.loadCount(for: rootURL) == 1
        }
        #expect(monitorLoadStarted)

        await viewModel.setDirectory(childURL)

        #expect(viewModel.currentURL == childURL)
        #expect(viewModel.items == [childItem])
        #expect(viewModel.backStack == [rootURL])
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func explicitRefreshQueuesBehindUserNavigation() async throws {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let childURL = URL(filePath: "/root/child", directoryHint: .isDirectory)
        let childItem = try PaneTestTemporaryDirectory().createFileItem(named: "child.txt")
        let fileBrowserService = MutableMockFileBrowserService(
            itemsByURL: [childURL: [childItem]],
            delayNanosecondsByURL: [childURL: 80_000_000]
        )
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: fileBrowserService
        )

        let navigation = Task { @MainActor in
            await viewModel.setDirectory(childURL)
        }
        let navigationStarted = try await waitUntil {
            viewModel.isLoading && fileBrowserService.loadCount(for: childURL) == 1
        }
        #expect(navigationStarted)

        await viewModel.refresh()
        await navigation.value
        let queuedRefreshCompleted = try await waitUntil {
            viewModel.currentURL == childURL &&
                fileBrowserService.loadCount(for: childURL) == 2 &&
                !viewModel.isLoading
        }

        #expect(queuedRefreshCompleted)
        #expect(viewModel.currentURL == childURL)
        #expect(viewModel.items == [childItem])
        #expect(viewModel.backStack == [rootURL])
        #expect(fileBrowserService.loadCount(for: rootURL) == 0)
        #expect(viewModel.isLoading == false)
    }

    @Test func cancelledDirectoryLoadDoesNotLeaveLoadingStateStuck() async throws {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let fileBrowserService = MutableMockFileBrowserService(
            delayNanosecondsByURL: [rootURL: 300_000_000]
        )
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: fileBrowserService
        )

        let load = Task { @MainActor in
            await viewModel.loadCurrentDirectory()
        }
        let loadStarted = try await waitUntil {
            viewModel.isLoading && fileBrowserService.loadCount(for: rootURL) == 1
        }
        #expect(loadStarted)

        load.cancel()
        await load.value

        #expect(viewModel.isLoading == false)
        #expect(viewModel.currentURL == rootURL)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func refreshDoesNotChangeNavigationHistory() async {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let childURL = URL(filePath: "/root/child", directoryHint: .isDirectory)
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: MockFileBrowserService()
        )
        await viewModel.setDirectory(childURL)
        let backStack = viewModel.backStack
        let forwardStack = viewModel.forwardStack

        await viewModel.refresh()

        #expect(viewModel.currentURL == childURL)
        #expect(viewModel.backStack == backStack)
        #expect(viewModel.forwardStack == forwardStack)
    }

    @Test func refreshPreservesSelectionForItemsStillInFolder() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let keptItem = try temporaryDirectory.createFileItem(named: "keep.txt")
        let removedItem = try temporaryDirectory.createFileItem(named: "remove.txt")
        let addedItem = try temporaryDirectory.createFileItem(named: "add.txt")
        let fileBrowserService = MutableMockFileBrowserService(itemsByURL: [
            temporaryDirectory.url: [keptItem, removedItem]
        ])
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: fileBrowserService
        )
        await viewModel.loadCurrentDirectory()
        viewModel.selectedItems = [keptItem, removedItem]
        fileBrowserService.setItems([keptItem, addedItem], for: temporaryDirectory.url)

        await viewModel.refresh()

        #expect(viewModel.items == [keptItem, addedItem])
        #expect(viewModel.selectedItems == [keptItem])
    }

    @Test func failedNavigationDoesNotChangeURLItemsOrHistory() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let existingItem = try temporaryDirectory.createFileItem(named: "existing.txt")
        let destinationURL = temporaryDirectory.url.appendingPathComponent("Missing", isDirectory: true)
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(
                itemsByURL: [temporaryDirectory.url: [existingItem]],
                errorByURL: [destinationURL: FileBrowserError.directoryNotFound(destinationURL)]
            )
        )
        await viewModel.loadCurrentDirectory()

        await viewModel.setDirectory(destinationURL)

        #expect(viewModel.currentURL == temporaryDirectory.url)
        #expect(viewModel.items == [existingItem])
        #expect(viewModel.backStack.isEmpty)
        #expect(viewModel.forwardStack.isEmpty)
        #expect(viewModel.errorMessage == "Missing could not be found.")
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

    @Test func openSelectedItemSurfacesWorkspaceOpenFailure() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let fileItem = try temporaryDirectory.createFileItem(named: "notes.txt")
        let workspaceService = MockWorkspaceService()
        workspaceService.openResult = false
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            workspaceService: workspaceService
        )
        viewModel.selectedItems = [fileItem]

        await viewModel.openSelectedItem()

        #expect(workspaceService.openedURLs == [fileItem.url])
        #expect(viewModel.errorMessage == "Could not open notes.txt.")
    }

    @Test func openWithApplicationSurfacesWorkspaceError() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let fileItem = try temporaryDirectory.createFileItem(named: "notes.txt")
        let applicationURL = URL(filePath: "/Applications/TextEdit.app")
        let workspaceService = MockWorkspaceService()
        workspaceService.openWithApplicationError = WorkspaceError.openWithApplicationFailed(
            fileItem.url,
            applicationURL,
            "Permission denied."
        )
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            workspaceService: workspaceService
        )

        await viewModel.open(fileItem, withApplication: applicationURL)

        #expect(workspaceService.openedWithApplicationRequests.map(\.url) == [fileItem.url])
        #expect(viewModel.errorMessage == "Could not open notes.txt with TextEdit: Permission denied.")
    }

    @Test func applicationsAvailableToOpenCachesOptionsByFileType() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createFileItem(named: "first.txt")
        let secondItem = try temporaryDirectory.createFileItem(named: "second.txt")
        let workspaceService = MockWorkspaceService()
        let textEditOption = ApplicationOption(
            name: "TextEdit",
            url: URL(filePath: "/Applications/TextEdit.app"),
            icon: nil
        )
        workspaceService.applicationOptions = [textEditOption]
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            workspaceService: workspaceService
        )

        let firstOptions = viewModel.applicationsAvailableToOpen(firstItem)
        let didLoadOptions = try await waitUntil {
            viewModel.applicationsAvailableToOpen(firstItem).map(\.url) == [textEditOption.url]
        }
        let secondOptions = viewModel.applicationsAvailableToOpen(secondItem)

        #expect(firstOptions.isEmpty)
        #expect(didLoadOptions)
        #expect(secondOptions.map(\.url) == [textEditOption.url])
        #expect(workspaceService.appsAvailableURLs == [firstItem.url])
        #expect(FilePaneViewModel.openWithCacheKey(for: firstItem) == FilePaneViewModel.openWithCacheKey(for: secondItem))
    }

    @Test func applicationOptionsCacheIsBounded() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let fullItems = try [
            temporaryDirectory.createFileItem(named: "first.cache-one"),
            temporaryDirectory.createFileItem(named: "second.cache-two"),
            temporaryDirectory.createFileItem(named: "third.cache-three")
        ]
        let items = try fullItems.map { try FileItem(essentialURL: $0.url) }
        let workspaceService = MockWorkspaceService()
        workspaceService.applicationOptions = [
            ApplicationOption(
                name: "Example",
                url: URL(filePath: "/Applications/Example.app"),
                icon: nil
            )
        ]
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            workspaceService: workspaceService,
            maximumApplicationOptionsCacheEntryCount: 2
        )

        items.forEach { _ = viewModel.applicationsAvailableToOpen($0) }
        let didLoadAllOptions = try await waitUntil {
            workspaceService.appsAvailableURLs.count == items.count &&
                viewModel.cachedApplicationOptionsCount == 2
        }

        #expect(didLoadAllOptions)
        #expect(viewModel.cachedApplicationOptionsCount == 2)
    }

    @Test func applicationsAvailableToOpenSkipsWorkspaceLookupForDirectories() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let directoryItem = try temporaryDirectory.createDirectoryItem(named: "Folder")
        let workspaceService = MockWorkspaceService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            workspaceService: workspaceService
        )

        let options = viewModel.applicationsAvailableToOpen(directoryItem)

        #expect(options.isEmpty)
        #expect(workspaceService.appsAvailableURLs.isEmpty)
    }

    @Test func openWithCacheKeySupportsFilesWithoutExtensions() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let fileItem = try temporaryDirectory.createFileItem(named: "Makefile")

        #expect(!FilePaneViewModel.openWithCacheKey(for: fileItem).isEmpty)
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

    @Test func copyItemsForContextMenuCopiesFileURLs() async throws {
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

        let copiedItemCount = viewModel.copyItemsForContextMenu(clickedItem: firstItem)

        #expect(copiedItemCount == 2)
        #expect(Set(workspaceService.copiedFileURLs) == Set([firstItem.url, secondItem.url]))
        #expect(viewModel.errorMessage == nil)
    }

    @Test func copySelectedItemsToPasteboardUsesVisibleSelectionOrder() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createFileItem(named: "Alpha.txt")
        let secondItem = try temporaryDirectory.createFileItem(named: "Beta.txt")
        let workspaceService = MockWorkspaceService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [secondItem, firstItem]
            ]),
            workspaceService: workspaceService
        )
        await viewModel.loadCurrentDirectory()
        viewModel.selectedItems = [secondItem, firstItem]

        let copiedItemCount = viewModel.copySelectedItemsToPasteboard()

        #expect(copiedItemCount == 2)
        #expect(workspaceService.copiedFileURLs == [firstItem.url, secondItem.url])
        #expect(viewModel.errorMessage == nil)
    }

    @Test func previewSelectedItemShowsErrorWhenNothingIsSelected() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let quickLookPreviewService = MockQuickLookPreviewService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            quickLookPreviewService: quickLookPreviewService
        )

        viewModel.previewSelectedItem()

        #expect(viewModel.errorMessage == "Select one file to preview.")
        #expect(quickLookPreviewService.previewedURLs.isEmpty)
    }

    @Test func previewSelectedItemShowsErrorWhenMultipleItemsAreSelected() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createFileItem(named: "first.txt")
        let secondItem = try temporaryDirectory.createFileItem(named: "second.txt")
        let quickLookPreviewService = MockQuickLookPreviewService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            quickLookPreviewService: quickLookPreviewService
        )
        viewModel.selectedItems = [firstItem, secondItem]

        viewModel.previewSelectedItem()

        #expect(viewModel.errorMessage == "Select only one file to preview.")
        #expect(quickLookPreviewService.previewedURLs.isEmpty)
    }

    @Test func previewSelectedItemShowsErrorForDirectory() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let directoryItem = try temporaryDirectory.createDirectoryItem(named: "Documents")
        let quickLookPreviewService = MockQuickLookPreviewService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            quickLookPreviewService: quickLookPreviewService
        )
        viewModel.selectedItems = [directoryItem]

        viewModel.previewSelectedItem()

        #expect(viewModel.errorMessage == "Select a file to preview.")
        #expect(quickLookPreviewService.previewedURLs.isEmpty)
    }

    @Test func previewSelectedItemPreviewsSelectedFile() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let fileItem = try temporaryDirectory.createFileItem(named: "notes.txt")
        let quickLookPreviewService = MockQuickLookPreviewService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(),
            quickLookPreviewService: quickLookPreviewService
        )
        viewModel.selectedItems = [fileItem]

        viewModel.previewSelectedItem()

        #expect(quickLookPreviewService.previewedURLs == [fileItem.url])
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
        #expect(viewModel.errorMessage?.contains("could not be found") == true)
    }

    @Test func loadCurrentDirectoryShowsMissingDirectoryMessageAndResetsLoading() async throws {
        let missingURL = URL(filePath: "/missing-folder", directoryHint: .isDirectory)
        let viewModel = FilePaneViewModel(
            currentURL: missingURL,
            fileBrowserService: MockFileBrowserService(errorByURL: [
                missingURL: FileBrowserError.directoryNotFound(missingURL)
            ])
        )

        await viewModel.loadCurrentDirectory()

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == "missing-folder could not be found.")
    }

    @Test func loadCurrentDirectoryShowsPermissionDeniedMessageAndResetsLoading() async throws {
        let protectedURL = URL(filePath: "/protected", directoryHint: .isDirectory)
        let viewModel = FilePaneViewModel(
            currentURL: protectedURL,
            fileBrowserService: MockFileBrowserService(errorByURL: [
                protectedURL: CocoaError(.fileReadNoPermission)
            ])
        )

        await viewModel.loadCurrentDirectory()

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == "You do not have permission to open protected.")
    }

    @Test func directoryMonitorChangeRefreshesCurrentDirectory() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let initialItem = try temporaryDirectory.createFileItem(named: "initial.txt")
        let addedItem = try temporaryDirectory.createFileItem(named: "added.txt")
        let fileBrowserService = MutableMockFileBrowserService(itemsByURL: [
            temporaryDirectory.url: [initialItem]
        ])
        let directoryMonitorService = MockDirectoryMonitorService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: fileBrowserService,
            directoryMonitorService: directoryMonitorService,
            directoryRefreshDebounceNanoseconds: 10_000_000
        )
        await viewModel.loadCurrentDirectory()
        fileBrowserService.setItems([initialItem, addedItem], for: temporaryDirectory.url)

        directoryMonitorService.emitChange(for: temporaryDirectory.url)
        let didRefresh = try await waitUntil {
            viewModel.items == [initialItem, addedItem]
                && fileBrowserService.loadCount(for: temporaryDirectory.url) == 2
        }

        #expect(didRefresh)
        #expect(viewModel.items == [initialItem, addedItem])
        #expect(fileBrowserService.loadCount(for: temporaryDirectory.url) == 2)
        #expect(viewModel.directoryFingerprintCheckCount == 1)
        #expect(viewModel.directoryFingerprintNoOpCount == 0)
    }

    @Test func directoryMonitorRapidChangesCoalesceIntoOneRefresh() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let initialItem = try temporaryDirectory.createFileItem(named: "initial.txt")
        let addedItem = try temporaryDirectory.createFileItem(named: "added.txt")
        let fileBrowserService = MutableMockFileBrowserService(itemsByURL: [
            temporaryDirectory.url: [initialItem]
        ])
        let directoryMonitorService = MockDirectoryMonitorService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: fileBrowserService,
            directoryMonitorService: directoryMonitorService,
            directoryRefreshDebounceNanoseconds: 20_000_000
        )
        await viewModel.loadCurrentDirectory()
        fileBrowserService.setItems([initialItem, addedItem], for: temporaryDirectory.url)

        directoryMonitorService.emitChange(for: temporaryDirectory.url)
        directoryMonitorService.emitChange(for: temporaryDirectory.url)
        directoryMonitorService.emitChange(for: temporaryDirectory.url)
        let didRefresh = try await waitUntil {
            viewModel.items == [initialItem, addedItem]
                && fileBrowserService.loadCount(for: temporaryDirectory.url) == 2
        }

        #expect(didRefresh)
        #expect(viewModel.items == [initialItem, addedItem])
        #expect(fileBrowserService.loadCount(for: temporaryDirectory.url) == 2)
        #expect(viewModel.directoryFingerprintCheckCount == 1)
        #expect(viewModel.directoryFingerprintNoOpCount == 0)
    }

    @Test func noOpDirectoryMonitorRefreshDoesNotRepublishVisibleItems() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let item = try temporaryDirectory.createFileItem(named: "stable.txt")
        let fileBrowserService = MutableMockFileBrowserService(itemsByURL: [
            temporaryDirectory.url: [item]
        ])
        let directoryMonitorService = MockDirectoryMonitorService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: fileBrowserService,
            directoryMonitorService: directoryMonitorService,
            directoryRefreshDebounceNanoseconds: 10_000_000
        )
        await viewModel.loadCurrentDirectory()
        let publicationCount = viewModel.visibleItemsPublicationCount
        let itemPublicationCount = viewModel.itemsPublicationCount

        directoryMonitorService.emitChange(for: temporaryDirectory.url)
        let didRefresh = try await waitUntil {
            fileBrowserService.loadCount(for: temporaryDirectory.url) == 2 &&
                viewModel.directoryFingerprintCheckCount == 1 &&
                !viewModel.isLoading
        }

        #expect(didRefresh)
        #expect(viewModel.visibleItems == [item])
        #expect(viewModel.visibleItemsPublicationCount == publicationCount)
        #expect(viewModel.itemsPublicationCount == itemPublicationCount)
        #expect(viewModel.directoryFingerprintCheckCount == 1)
        #expect(viewModel.directoryFingerprintNoOpCount == 1)
    }

    @Test func directoryChangeRestartsDirectoryMonitor() async throws {
        let rootURL = URL(filePath: "/root", directoryHint: .isDirectory)
        let childURL = URL(filePath: "/root/child", directoryHint: .isDirectory)
        let directoryMonitorService = MockDirectoryMonitorService()
        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: MockFileBrowserService(),
            directoryMonitorService: directoryMonitorService
        )
        let initialToken = try #require(directoryMonitorService.tokens.first)

        await viewModel.setDirectory(childURL)

        #expect(directoryMonitorService.monitoredURLs == [rootURL, childURL])
        #expect(initialToken.isCancelled)
        #expect(directoryMonitorService.tokens.last?.isCancelled == false)
    }

    @Test func tabSwitchRestartsDirectoryMonitorForActiveTabDirectory() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let childDirectory = try temporaryDirectory.createDirectoryItem(named: "Child")
        let directoryMonitorService = MockDirectoryMonitorService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: MockFileBrowserService(itemsByURL: [
                temporaryDirectory.url: [childDirectory],
                childDirectory.url: []
            ]),
            directoryMonitorService: directoryMonitorService
        )
        let firstTabID = viewModel.activeTabID

        await viewModel.newTab()
        await viewModel.setDirectory(childDirectory.url)
        await viewModel.switchToTab(firstTabID)

        let previousTokensCancelled = directoryMonitorService.tokens
            .dropLast()
            .allSatisfy { $0.isCancelled }

        #expect(directoryMonitorService.monitoredURLs.last == temporaryDirectory.url)
        #expect(previousTokensCancelled)
        #expect(directoryMonitorService.tokens.last?.isCancelled == false)
    }

    @Test func directoryMonitorMissingFolderClearsStaleItemsAndShowsError() async throws {
        let temporaryDirectory = try PaneTestTemporaryDirectory()
        let staleItem = try temporaryDirectory.createFileItem(named: "stale.txt")
        let fileBrowserService = MutableMockFileBrowserService(itemsByURL: [
            temporaryDirectory.url: [staleItem]
        ])
        let directoryMonitorService = MockDirectoryMonitorService()
        let viewModel = FilePaneViewModel(
            currentURL: temporaryDirectory.url,
            fileBrowserService: fileBrowserService,
            directoryMonitorService: directoryMonitorService,
            directoryRefreshDebounceNanoseconds: 10_000_000
        )
        await viewModel.loadCurrentDirectory()
        viewModel.selectedItems = [staleItem]
        fileBrowserService.setError(FileBrowserError.directoryNotFound(temporaryDirectory.url), for: temporaryDirectory.url)

        directoryMonitorService.emitChange(for: temporaryDirectory.url)
        let didRefresh = try await waitUntil {
            viewModel.items.isEmpty
                && viewModel.selectedItems.isEmpty
                && viewModel.errorMessage == "\(temporaryDirectory.url.openPaneDisplayName) could not be found."
        }

        #expect(didRefresh)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.selectedItems.isEmpty)
        #expect(viewModel.errorMessage == "\(temporaryDirectory.url.openPaneDisplayName) could not be found.")
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    intervalNanoseconds: UInt64 = 10_000_000,
    condition: () -> Bool
) async throws -> Bool {
    var remainingNanoseconds = timeoutNanoseconds

    while !condition() {
        guard remainingNanoseconds > 0 else {
            return false
        }

        let sleepNanoseconds = min(intervalNanoseconds, remainingNanoseconds)
        try await Task.sleep(nanoseconds: sleepNanoseconds)
        remainingNanoseconds -= sleepNanoseconds
    }

    return true
}

@MainActor
private final class MockQuickLookPreviewService: QuickLookPreviewServicing {
    private(set) var previewedURLs: [URL] = []

    func preview(url: URL) {
        previewedURLs.append(url)
    }
}

@MainActor
private final class MockWorkspaceService: WorkspaceServicing, @unchecked Sendable {
    private(set) var openedURLs: [URL] = []
    private(set) var openedWithApplicationRequests: [(url: URL, applicationURL: URL)] = []
    private(set) var chooseApplicationURLs: [URL] = []
    private(set) var revealedURLs: [URL] = []
    private(set) var sharedURLs: [URL] = []
    private(set) var copiedFileURLs: [URL] = []
    private(set) var copiedPathURLs: [URL] = []
    private(set) var copiedText: [String] = []
    private(set) var appsAvailableURLs: [URL] = []
    var applicationOptions: [ApplicationOption] = []
    var pasteboardFileURLs: [URL] = []
    var openResult = true
    var openWithApplicationError: Error?

    func open(url: URL) -> Bool {
        openedURLs.append(url)
        return openResult
    }

    func appsAvailableToOpen(url: URL) async -> [ApplicationOption] {
        appsAvailableURLs.append(url)
        return applicationOptions
    }

    func open(url: URL, withApplication applicationURL: URL) async throws {
        openedWithApplicationRequests.append((url, applicationURL))

        if let openWithApplicationError {
            throw openWithApplicationError
        }
    }

    func chooseApplicationAndOpen(url: URL) {
        chooseApplicationURLs.append(url)
    }

    func revealInFinder(urls: [URL]) {
        revealedURLs.append(contentsOf: urls)
    }

    func share(urls: [URL]) throws {
        sharedURLs.append(contentsOf: urls)
    }

    func copyFileURLs(_ urls: [URL]) {
        copiedFileURLs.append(contentsOf: urls)
    }

    func fileURLsForPasteboard() -> [URL] {
        pasteboardFileURLs
    }

    func copyPath(url: URL) {
        copiedPathURLs.append(url)
    }

    func copyText(_ text: String) {
        copiedText.append(text)
    }
}

nonisolated private struct MockFileBrowserService: FileBrowserServicing {
    var itemsByURL: [URL: [FileItem]] = [:]
    var errorURLs: Set<URL> = []
    var errorByURL: [URL: any Error & Sendable] = [:]

    nonisolated func contentsOfDirectory(at url: URL, includeHiddenFiles: Bool) async throws -> [FileItem] {
        if let error = errorByURL[url] {
            throw error
        }

        if errorURLs.contains(url) {
            throw CocoaError(.fileReadNoSuchFile)
        }

        return itemsByURL[url] ?? []
    }
}

nonisolated private struct DelayedMockFileBrowserService: FileBrowserServicing {
    var itemsByURL: [URL: [FileItem]] = [:]
    var errorByURL: [URL: any Error & Sendable] = [:]
    var delayNanosecondsByURL: [URL: UInt64] = [:]

    nonisolated func contentsOfDirectory(at url: URL, includeHiddenFiles: Bool) async throws -> [FileItem] {
        if let delayNanoseconds = delayNanosecondsByURL[url] {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        if let error = errorByURL[url] {
            throw error
        }

        return itemsByURL[url] ?? []
    }
}

nonisolated private final class MutableMockFileBrowserService: FileBrowserServicing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.openpane.tests.mutable-file-browser")
    private var itemsByURL: [URL: [FileItem]]
    private var errorByURL: [URL: any Error & Sendable]
    private var delayNanosecondsByURL: [URL: UInt64]
    private var loadCountsByURL: [URL: Int]

    init(
        itemsByURL: [URL: [FileItem]] = [:],
        errorByURL: [URL: any Error & Sendable] = [:],
        delayNanosecondsByURL: [URL: UInt64] = [:]
    ) {
        self.itemsByURL = itemsByURL
        self.errorByURL = errorByURL
        self.delayNanosecondsByURL = delayNanosecondsByURL
        self.loadCountsByURL = [:]
    }

    nonisolated func contentsOfDirectory(at url: URL, includeHiddenFiles: Bool) async throws -> [FileItem] {
        let response = queue.sync { () -> (items: [FileItem], error: (any Error & Sendable)?, delay: UInt64?) in
            loadCountsByURL[url, default: 0] += 1
            return (itemsByURL[url] ?? [], errorByURL[url], delayNanosecondsByURL[url])
        }

        if let delay = response.delay {
            try await Task.sleep(nanoseconds: delay)
        }

        if let error = response.error {
            throw error
        }

        return response.items
    }

    nonisolated func setItems(_ items: [FileItem], for url: URL) {
        queue.sync {
            itemsByURL[url] = items
            errorByURL[url] = nil
        }
    }

    nonisolated func setError(_ error: any Error & Sendable, for url: URL) {
        queue.sync {
            errorByURL[url] = error
        }
    }

    nonisolated func loadCount(for url: URL) -> Int {
        queue.sync {
            loadCountsByURL[url, default: 0]
        }
    }
}

nonisolated private final class MockDirectoryMonitorService: DirectoryMonitorServicing, @unchecked Sendable {
    private struct Registration {
        let url: URL
        let onChange: @Sendable () -> Void
        let token: MockDirectoryMonitorToken
    }

    private let queue = DispatchQueue(label: "com.openpane.tests.directory-monitor")
    private var registrations: [Registration] = []

    nonisolated var monitoredURLs: [URL] {
        queue.sync {
            registrations.map(\.url)
        }
    }

    nonisolated var tokens: [MockDirectoryMonitorToken] {
        queue.sync {
            registrations.map(\.token)
        }
    }

    nonisolated func monitorDirectory(
        at url: URL,
        onChange: @escaping @Sendable () -> Void
    ) -> any DirectoryMonitorToken {
        let token = MockDirectoryMonitorToken()

        queue.sync {
            registrations.append(Registration(url: url, onChange: onChange, token: token))
        }

        return token
    }

    nonisolated func emitChange(for url: URL? = nil) {
        let callbacks = queue.sync {
            registrations
                .filter { registration in
                    !registration.token.isCancelled &&
                        (url == nil || registration.url == url)
                }
                .map(\.onChange)
        }

        callbacks.forEach { callback in
            callback()
        }
    }
}

nonisolated private final class MockDirectoryMonitorToken: DirectoryMonitorToken, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.openpane.tests.directory-monitor-token")
    private var isCancelledStorage = false

    nonisolated var isCancelled: Bool {
        queue.sync {
            isCancelledStorage
        }
    }

    nonisolated func cancel() {
        queue.sync {
            isCancelledStorage = true
        }
    }
}

nonisolated private struct MockFileSearchService: FileSearchServicing {
    var results: [FileItem] = []
    var error: (any Error & Sendable)?

    nonisolated func search(
        root: URL,
        query: String,
        includeHiddenFiles: Bool,
        limit: Int
    ) async throws -> [FileItem] {
        if let error {
            throw error
        }

        return Array(results.prefix(limit))
    }
}

nonisolated private struct DelayedMockFileSearchService: FileSearchServicing {
    var results: [FileItem]
    var delayNanoseconds: UInt64

    nonisolated func search(
        root: URL,
        query: String,
        includeHiddenFiles: Bool,
        limit: Int
    ) async throws -> [FileItem] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return Array(results.prefix(limit))
    }
}

nonisolated private struct ContentSearchMockFileSearchService: FileSearchServicing {
    let response: FileSearchResponse

    nonisolated func search(
        root: URL,
        query: String,
        includeHiddenFiles: Bool,
        limit: Int
    ) async throws -> [FileItem] {
        response.results.map(\.item)
    }

    nonisolated func search(
        root: URL,
        query: String,
        kind: FileSearchKind,
        includeHiddenFiles: Bool,
        limit: Int
    ) async throws -> FileSearchResponse {
        kind == .contents
            ? response
            : FileSearchResponse(
                results: response.results.map { FileSearchResult(item: $0.item, contentMatch: nil) },
                skippedFileCount: 0
            )
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
        try createFileItem(named: relativePath, contents: relativePath)
    }

    func createFileItem(named relativePath: String, contents: String) throws -> FileItem {
        let fileURL = url.appendingPathComponent(relativePath)
        let parentURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let didCreateFile = FileManager.default.createFile(atPath: fileURL.path, contents: Data(contents.utf8))
        #expect(didCreateFile)

        return try FileItem(url: fileURL)
    }
}
