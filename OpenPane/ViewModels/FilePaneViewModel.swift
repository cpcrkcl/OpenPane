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

nonisolated enum FileSortOption: String, CaseIterable, Codable, Identifiable, Sendable {
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

nonisolated enum FilePaneSearchMode: String, CaseIterable, Identifiable, Sendable {
    case filter
    case names
    case contents

    /// Source-compatible spelling for the original recursive filename mode.
    static var subtree: Self {
        .names
    }

    var id: Self {
        self
    }

    var displayName: String {
        switch self {
        case .filter:
            return "Filter"
        case .names:
            return "Names"
        case .contents:
            return "Contents"
        }
    }

    var placeholder: String {
        switch self {
        case .filter:
            return "Filter"
        case .names:
            return "Search names"
        case .contents:
            return "Search contents"
        }
    }

    var isSubtreeSearch: Bool {
        self != .filter
    }

    var fileSearchKind: FileSearchKind? {
        switch self {
        case .filter:
            nil
        case .names:
            .filename
        case .contents:
            .contents
        }
    }
}

nonisolated enum FileSortDirection: String, CaseIterable, Codable, Identifiable, Sendable {
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

private nonisolated struct VisibleItemsRequest: Sendable {
    let sourceItems: [FileItem]
    let filterText: String?
    let sortOption: FileSortOption
    let sortDirection: FileSortDirection
    let shouldSortSourceItems: Bool
}

private nonisolated struct VisibleItemsComputation: Sendable {
    let sortedSourceItems: [FileItem]
    let visibleItems: [FileItem]
}

typealias FileMetadataEnricher = @Sendable ([FileItem]) async throws -> [FileItem]

@MainActor
final class FilePaneViewModel: ObservableObject {
    private enum DirectoryLoadPriority: Int {
        case monitorRefresh
        case explicitRefresh
        case userNavigation
    }

    @Published var currentLocation: PaneLocation {
        didSet {
            guard !isSynchronizingLocation else {
                return
            }

            isSynchronizingLocation = true
            currentURL = currentLocation.fileURL ?? PaneLocation.networkPlaceholderURL
            updateActiveTab { tab in
                tab.location = currentLocation
            }
            isSynchronizingLocation = false
        }
    }

    // Kept as a compatibility convenience for the local-file API and existing callers.
    // Network locations expose the harmless /Network placeholder and must use
    // currentLocation/fileURL before performing filesystem work.
    @Published var currentURL: URL {
        didSet {
            guard !isSynchronizingLocation else {
                return
            }

            isSynchronizingLocation = true
            currentLocation = .file(currentURL)
            updateActiveTab { tab in
                tab.location = currentLocation
            }
            isSynchronizingLocation = false
        }
    }

    @Published var items: [FileItem] {
        didSet {
            #if DEBUG
            itemsPublicationCount += 1
            PerformanceDiagnostics.shared.recordItemArrayReplacement()
            #endif
            scheduleVisibleItemsRecompute(invalidateSortedItems: true)
        }
    }

    @Published var selectedItems: Set<FileItem> {
        didSet {
            if !isApplyingFileListSelection {
                synchronizeFileListSelection()
            }
        }
    }

    @Published var tabs: [FilePaneTab] {
        didSet {
            #if DEBUG
            tabsPublicationCount += 1
            #endif
        }
    }
    @Published var activeTabID: FilePaneTab.ID
    @Published var isLoading: Bool
    @Published var errorMessage: String?
    @Published var includeHiddenFiles: Bool
    @Published var searchText: String {
        didSet {
            if searchText != oldValue,
               isShowingRecursiveSearchResults || recursiveSearchTask != nil || pendingSubtreeSearch {
                clearRecursiveSearch(clearSelection: false)
            }
            scheduleVisibleItemsRecompute(debounce: searchMode == .filter)
        }
    }
    @Published var searchMode: FilePaneSearchMode = .filter {
        didSet {
            guard searchMode != oldValue else {
                return
            }

            // Recursive results are specific to the search kind that produced
            // them. Invalidate both completed and in-flight work when moving
            // between Names and Contents so an old response cannot be shown
            // under the newly selected mode.
            if searchMode.fileSearchKind != oldValue.fileSearchKind,
               isShowingRecursiveSearchResults || recursiveSearchTask != nil || pendingSubtreeSearch {
                clearRecursiveSearch(clearSelection: false)
            }
            scheduleVisibleItemsRecompute(debounce: searchMode == .filter)
        }
    }
    @Published private(set) var isSearchingSubtree = false
    @Published var sortOption: FileSortOption {
        didSet {
            scheduleVisibleItemsRecompute(invalidateSortedItems: true, preferCachedSortInput: true)
        }
    }
    @Published var sortDirection: FileSortDirection {
        didSet {
            scheduleVisibleItemsRecompute(invalidateSortedItems: true, preferCachedSortInput: true)
        }
    }
    @Published var recursiveSearchResults: [FileItem] {
        didSet {
            scheduleVisibleItemsRecompute(invalidateSortedItems: true)
        }
    }
    @Published private(set) var recursiveSearchContentMatches: [FileItem.ID: FileContentMatch]
    @Published private(set) var recursiveSearchSkippedFileCount: Int
    @Published var isShowingRecursiveSearchResults: Bool {
        didSet {
            scheduleVisibleItemsRecompute(invalidateSortedItems: true)
        }
    }
    @Published private(set) var backStack: [URL]
    @Published private(set) var forwardStack: [URL]
    @Published private(set) var visibleItems: [FileItem]
    @Published private(set) var fileListSelection: FileListSelectionController
    @Published private(set) var calculatedFolderSizes: [URL: FolderSizeResult]
    @Published private(set) var calculatingFolderSizeURLs: Set<URL>
    @Published private(set) var applicationOptionsCacheGeneration: Int

    private let fileBrowserService: any FileBrowserServicing
    private let fileSearchService: any FileSearchServicing
    private let workspaceService: any WorkspaceServicing
    private let quickLookPreviewService: any QuickLookPreviewServicing
    private let directoryMonitorService: any DirectoryMonitorServicing
    private let folderSizeService: any FolderSizeServicing
    private let metadataEnricher: FileMetadataEnricher
    private let directoryRefreshDebounceNanoseconds: UInt64
    private let visibleItemsSearchDebounceNanoseconds: UInt64
    private let maximumApplicationOptionsCacheEntryCount: Int
    private let directoryNavigationSubject = PassthroughSubject<URL, Never>()
    private var directoryMonitorToken: (any DirectoryMonitorToken)?
    private var directoryMonitorRefreshTask: Task<Void, Never>?
    private var directoryLoadTask: Task<DirectorySnapshot, Error>?
    private var recursiveSearchTask: Task<FileSearchResponse, Error>?
    private var visibleItemsTask: Task<Void, Never>?
    private var metadataEnrichmentTask: Task<Void, Never>?
    private var folderSizeTasksByURL: [URL: Task<Void, Never>] = [:]
    private var hasPendingDirectoryMonitorRefresh = false
    private var hasPendingExplicitRefresh = false
    private var pendingSubtreeSearch = false
    private var pendingSubtreeSearchLimit = FileSearchService.defaultLimit
    private var pendingSubtreeSearchContinuations: [CheckedContinuation<Void, Never>] = []
    private var currentDirectoryFingerprint: DirectoryFingerprint?
    private var activeDirectoryLoadPriority: DirectoryLoadPriority?
    private var requestGeneration = 0
    private var recursiveSearchGeneration = 0
    private var visibleItemsGeneration = 0
    private var sortedItemsSourceGeneration = 0
    private var sortedItemsCacheGeneration = -1
    private var sortedItemsCache: [FileItem] = []
    private var tabCacheRecency: [FilePaneTab.ID]
    private var applicationOptionsByTypeKey: [String: [ApplicationOption]] = [:]
    private var applicationOptionsKeysInRecencyOrder: [String] = []
    private var applicationOptionsLoadTasksByTypeKey: [String: Task<Void, Never>] = [:]
    private var isApplyingFileListSelection = false
    private var isSynchronizingLocation = false
    private var locationBackStack: [PaneLocation]
    private var locationForwardStack: [PaneLocation]

    #if DEBUG
    private(set) var visibleItemsRecomputeCount = 0
    private(set) var visibleItemsPublicationCount = 0
    private(set) var itemsPublicationCount = 0
    private(set) var tabsPublicationCount = 0
    private(set) var metadataEnrichmentPublicationCount = 0
    private(set) var directoryFingerprintCheckCount = 0
    private(set) var directoryFingerprintNoOpCount = 0
    var cachedApplicationOptionsCount: Int { applicationOptionsByTypeKey.count }
    #endif

    private nonisolated static let defaultDirectoryRefreshDebounceNanoseconds: UInt64 = 250_000_000
    private nonisolated static let defaultVisibleItemsSearchDebounceNanoseconds: UInt64 = 150_000_000
    private nonisolated static let maximumCachedItemsPerTab = 5_000
    private nonisolated static let maximumCachedBackgroundTabCount = 4
    private nonisolated static let defaultMaximumApplicationOptionsCacheEntryCount = 64

    var canGoBack: Bool {
        !locationBackStack.isEmpty
    }

    var canGoForward: Bool {
        !locationForwardStack.isEmpty
    }

    var isFileBackedLocation: Bool {
        currentLocation.isFileBacked
    }

    var fileURL: URL? {
        currentLocation.fileURL
    }

    var filteredItems: [FileItem] {
        visibleItems
    }

    /// Emits only after a real filesystem navigation has completed. Refreshes,
    /// tab switches, and search state changes deliberately do not emit.
    var directoryNavigationDidComplete: AnyPublisher<URL, Never> {
        directoryNavigationSubject.eraseToAnyPublisher()
    }

    var focusedFileListItemID: FileItem.ID? {
        fileListSelection.focusedID
    }

    var orderedSelectedItems: [FileItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: visibleItems.map { ($0.id, $0) })
        return fileListSelection.orderedSelectionIDs.compactMap { itemsByID[$0] }
    }

    init(
        currentURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileBrowserService: any FileBrowserServicing = FileBrowserService(),
        fileSearchService: any FileSearchServicing = FileSearchService(),
        workspaceService: any WorkspaceServicing = WorkspaceService(),
        quickLookPreviewService: (any QuickLookPreviewServicing)? = nil,
        directoryMonitorService: (any DirectoryMonitorServicing)? = nil,
        folderSizeService: any FolderSizeServicing = FolderSizeService(),
        directoryRefreshDebounceNanoseconds: UInt64 = FilePaneViewModel.defaultDirectoryRefreshDebounceNanoseconds,
        visibleItemsSearchDebounceNanoseconds: UInt64 = FilePaneViewModel.defaultVisibleItemsSearchDebounceNanoseconds,
        metadataEnricher: @escaping FileMetadataEnricher = FilePaneViewModel.enrichMetadata,
        maximumApplicationOptionsCacheEntryCount: Int = FilePaneViewModel.defaultMaximumApplicationOptionsCacheEntryCount
    ) {
        self.currentURL = currentURL
        self.currentLocation = .file(currentURL)
        self.items = []
        self.selectedItems = []
        let initialTab = FilePaneTab(location: .file(currentURL))
        self.tabs = [initialTab]
        self.activeTabID = initialTab.id
        self.isLoading = false
        self.errorMessage = nil
        self.includeHiddenFiles = false
        self.searchText = ""
        self.sortOption = .name
        self.sortDirection = .ascending
        self.recursiveSearchResults = []
        self.recursiveSearchContentMatches = [:]
        self.recursiveSearchSkippedFileCount = 0
        self.isShowingRecursiveSearchResults = false
        self.backStack = []
        self.forwardStack = []
        self.locationBackStack = []
        self.locationForwardStack = []
        self.visibleItems = []
        self.fileListSelection = FileListSelectionController()
        self.tabCacheRecency = [initialTab.id]
        self.calculatedFolderSizes = [:]
        self.calculatingFolderSizeURLs = []
        self.applicationOptionsCacheGeneration = 0
        self.fileBrowserService = fileBrowserService
        self.fileSearchService = fileSearchService
        self.workspaceService = workspaceService
        self.quickLookPreviewService = quickLookPreviewService ?? QuickLookPreviewService.shared
        self.directoryMonitorService = directoryMonitorService ?? Self.defaultDirectoryMonitorService()
        self.folderSizeService = folderSizeService
        self.metadataEnricher = metadataEnricher
        self.directoryRefreshDebounceNanoseconds = directoryRefreshDebounceNanoseconds
        self.visibleItemsSearchDebounceNanoseconds = visibleItemsSearchDebounceNanoseconds
        self.maximumApplicationOptionsCacheEntryCount = max(1, maximumApplicationOptionsCacheEntryCount)
        scheduleVisibleItemsRecompute(invalidateSortedItems: true)
        restartDirectoryMonitor()
    }

    convenience init(location: PaneLocation) {
        self.init(currentURL: location.fileURL ?? FileManager.default.homeDirectoryForCurrentUser)
        if location == .network {
            currentLocation = .network
            clearFileLocationState()
        }
    }

    deinit {
        directoryMonitorToken?.cancel()
        directoryMonitorRefreshTask?.cancel()
        directoryLoadTask?.cancel()
        recursiveSearchTask?.cancel()
        visibleItemsTask?.cancel()
        metadataEnrichmentTask?.cancel()
        applicationOptionsLoadTasksByTypeKey.values.forEach { $0.cancel() }
        folderSizeTasksByURL.values.forEach { $0.cancel() }
    }

    func loadCurrentDirectory() async {
        await loadCurrentDirectory(priority: .explicitRefresh)
    }

    private func loadCurrentDirectory(
        priority: DirectoryLoadPriority,
        prefetchedSnapshot: DirectorySnapshot? = nil
    ) async {
        guard let requestURL = fileURL else {
            return
        }

        if let activeDirectoryLoadPriority,
           activeDirectoryLoadPriority.rawValue > priority.rawValue {
            switch priority {
            case .monitorRefresh:
                hasPendingDirectoryMonitorRefresh = true
            case .explicitRefresh:
                hasPendingExplicitRefresh = true
            case .userNavigation:
                break
            }
            return
        }

        let requestTabID = activeTabID
        let generation = nextRequestGeneration(
            cancelDirectoryMonitorRefresh: priority != .monitorRefresh
        )
        activeDirectoryLoadPriority = priority
        let wasDirty = activeTabIsDirty
        let selectedURLs = Set(selectedItems.map { $0.url.standardizedFileURL })
        isLoading = true
        errorMessage = nil
        clearRecursiveSearch(clearSelection: false, invalidateRequests: false)
        defer {
            if generation == requestGeneration {
                directoryLoadTask = nil
                activeDirectoryLoadPriority = nil
                isLoading = false
                schedulePendingDirectoryRefreshIfNeeded()
                runPendingSubtreeSearchIfNeeded()
            }
        }

        do {
            let snapshot: DirectorySnapshot
            if let prefetchedSnapshot {
                snapshot = prefetchedSnapshot
            } else {
                snapshot = try await loadDirectorySnapshot(
                    at: requestURL,
                    includeFingerprint: false,
                    priority: .userInitiated
                )
            }
            guard isCurrentRequest(generation, tabID: requestTabID, url: requestURL) else {
                return
            }

            let loadedItems = snapshot.items
            let didReplaceItems = replaceItemsIfChanged(loadedItems)
            selectedItems = Set(loadedItems.filter { selectedURLs.contains($0.url.standardizedFileURL) })
            if didReplaceItems {
                await waitForVisibleItemsUpdate()
            }
            let fingerprint: DirectoryFingerprint
            if let snapshotFingerprint = snapshot.fingerprint {
                fingerprint = snapshotFingerprint
            } else {
                fingerprint = await Self.directoryFingerprint(
                    for: loadedItems,
                    at: requestURL
                )
            }
            guard isCurrentRequest(generation, tabID: requestTabID, url: requestURL) else {
                return
            }
            currentDirectoryFingerprint = fingerprint
            setActiveTabDirty(false)
            startMetadataEnrichmentIfNeeded(
                for: loadedItems,
                generation: generation,
                tabID: requestTabID,
                directoryURL: requestURL
            )
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentRequest(generation, tabID: requestTabID, url: requestURL) else {
                return
            }

            currentDirectoryFingerprint = nil
            let didReplaceItems = replaceItemsIfChanged([])
            selectedItems = []
            if didReplaceItems {
                await waitForVisibleItemsUpdate()
            }
            if wasDirty {
                setActiveTabDirty(true)
            }
            errorMessage = Self.userReadableError(for: error, at: requestURL)
        }
    }

    func refresh() async {
        guard isFileBackedLocation else {
            return
        }

        invalidateFolderSizeCacheForCurrentDirectory()
        await loadCurrentDirectory()
    }

    func newTab() async {
        saveActiveTabState()
        let tab = FilePaneTab(location: currentLocation)
        tabs.append(tab)
        applyTab(tab)
        await loadCurrentDirectory(priority: .userNavigation)
    }

    func closeTab(_ id: FilePaneTab.ID) async {
        guard tabs.count > 1,
              let closingIndex = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }

        let isClosingActiveTab = id == activeTabID
        tabs.remove(at: closingIndex)
        tabCacheRecency.removeAll { $0 == id }

        guard isClosingActiveTab else {
            return
        }

        let nextIndex = min(closingIndex, tabs.count - 1)
        applyTab(tabs[nextIndex])

        if items.isEmpty || activeTabIsDirty {
            await loadCurrentDirectory(priority: .userNavigation)
        }
    }

    func switchToTab(_ id: FilePaneTab.ID) async {
        guard id != activeTabID,
              let tab = tabs.first(where: { $0.id == id }) else {
            return
        }

        saveActiveTabState()
        applyTab(tab)

        if items.isEmpty || activeTabIsDirty {
            await loadCurrentDirectory(priority: .userNavigation)
        }
    }

    func detachTab(_ id: FilePaneTab.ID) -> FilePaneTab? {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        saveActiveTabState()
        let removedTab = tabs.remove(at: index)
        tabCacheRecency.removeAll { $0 == id }

        if activeTabID == id {
            let nextIndex = min(index, tabs.count - 1)
            applyTab(tabs[nextIndex])
        }

        return removedTab
    }

    func receiveTab(_ tab: FilePaneTab, at index: Int? = nil) {
        guard !tabs.contains(where: { $0.id == tab.id }) else {
            return
        }

        saveActiveTabState()
        if let index {
            let insertionIndex = boundedTabInsertionIndex(index)
            tabs.insert(tab, at: insertionIndex)
        } else {
            tabs.append(tab)
        }
        applyTab(tab)
    }

    func containsTab(_ id: FilePaneTab.ID) -> Bool {
        tabs.contains { $0.id == id }
    }

    func canDetachTab(_ id: FilePaneTab.ID) -> Bool {
        tabs.count > 1 && containsTab(id)
    }

    func reorderTab(_ id: FilePaneTab.ID, toIndex: Int) {
        guard tabs.count > 1,
              let sourceIndex = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }

        saveActiveTabState()
        let tab = tabs.remove(at: sourceIndex)
        let insertionIndex = boundedTabInsertionIndex(toIndex)
        tabs.insert(tab, at: insertionIndex)
    }

    var searchStatusText: String? {
        if isSearchingSubtree {
            return "Searching…"
        }

        guard isShowingRecursiveSearchResults else {
            return nil
        }

        let count = recursiveSearchResults.count
        let resultText = count == 1 ? "1 result" : "\(count) results"
        guard recursiveSearchSkippedFileCount > 0 else {
            return resultText
        }

        let skippedText = recursiveSearchSkippedFileCount == 1
            ? "1 file skipped"
            : "\(recursiveSearchSkippedFileCount) files skipped"
        return "\(resultText) • \(skippedText)"
    }

    var isShowingContentSearchResults: Bool {
        isShowingRecursiveSearchResults && !recursiveSearchContentMatches.isEmpty
    }

    func performRecursiveSearch(limit: Int = FileSearchService.defaultLimit) async {
        guard let requestURL = fileURL else {
            errorMessage = "Recursive search is unavailable on the Network page."
            return
        }

        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSearchText.isEmpty else {
            errorMessage = "Enter a search term."
            return
        }

        if activeDirectoryLoadPriority == .userNavigation {
            pendingSubtreeSearch = true
            pendingSubtreeSearchLimit = limit
            isSearchingSubtree = true
            await withCheckedContinuation { continuation in
                pendingSubtreeSearchContinuations.append(continuation)
            }
            return
        }

        // Keep the original programmatic/action behavior compatible: an
        // explicit recursive search from Filter mode is a filename search.
        // The Contents mode remains opt-in through the segmented control.
        let kind = searchMode.fileSearchKind ?? .filename

        await executeSubtreeSearch(
            root: requestURL,
            query: trimmedSearchText,
            kind: kind,
            limit: limit
        )
    }

    func triggerSubtreeSearch() async {
        searchMode = .names
        await performRecursiveSearch()
    }

    func navigateToPath(_ path: String) async -> Bool {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            errorMessage = "Enter a path."
            return false
        }

        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        guard expandedPath.hasPrefix("/") else {
            errorMessage = "Enter an absolute path or a path beginning with ~."
            return false
        }

        let url = URL(fileURLWithPath: expandedPath, isDirectory: true)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            errorMessage = "The folder doesn’t exist or isn’t accessible."
            return false
        }

        errorMessage = nil
        let destinationURL = url.standardizedFileURL
        await setDirectory(destinationURL)
        return fileURL?.standardizedFileURL == destinationURL && errorMessage == nil
    }

    private func executeSubtreeSearch(
        root requestURL: URL,
        query trimmedSearchText: String,
        kind: FileSearchKind,
        limit: Int
    ) async {
        let requestTabID = activeTabID
        let generation = nextRecursiveSearchGeneration()
        isSearchingSubtree = true
        errorMessage = nil
        selectedItems = []
        defer {
            if generation == recursiveSearchGeneration {
                recursiveSearchTask = nil
                isSearchingSubtree = false
            }
        }

        do {
            let fileSearchService = fileSearchService
            let includeHiddenFiles = includeHiddenFiles
            let task = Task {
                try await fileSearchService.search(
                    root: requestURL,
                    query: trimmedSearchText,
                    kind: kind,
                    includeHiddenFiles: includeHiddenFiles,
                    limit: limit
                )
            }
            recursiveSearchTask = task
            let searchResponse = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }

            guard isCurrentRecursiveSearch(generation, tabID: requestTabID, url: requestURL),
                  searchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedSearchText else {
                return
            }

            recursiveSearchResults = searchResponse.results.map(\.item)
            recursiveSearchContentMatches = Dictionary(
                uniqueKeysWithValues: searchResponse.results.compactMap { result in
                    result.contentMatch.map { (result.item.id, $0) }
                }
            )
            recursiveSearchSkippedFileCount = searchResponse.skippedFileCount
            isShowingRecursiveSearchResults = true
            await waitForVisibleItemsUpdate()
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentRecursiveSearch(generation, tabID: requestTabID, url: requestURL) else {
                return
            }

            recursiveSearchResults = []
            recursiveSearchContentMatches = [:]
            recursiveSearchSkippedFileCount = 0
            isShowingRecursiveSearchResults = false
            await waitForVisibleItemsUpdate()
            errorMessage = Self.userReadableError(for: error, at: requestURL)
        }
    }

    private func runPendingSubtreeSearchIfNeeded() {
        guard pendingSubtreeSearch else {
            return
        }

        pendingSubtreeSearch = false
        let limit = pendingSubtreeSearchLimit
        let continuations = pendingSubtreeSearchContinuations
        pendingSubtreeSearchContinuations = []

        Task { [weak self] in
            guard let self else {
                continuations.forEach { $0.resume() }
                return
            }
            await self.performRecursiveSearch(limit: limit)
            continuations.forEach { $0.resume() }
        }
    }

    func clearRecursiveSearch() {
        clearRecursiveSearch(clearSelection: true)
    }

    func clearSearch() {
        searchText = ""
        clearRecursiveSearch(clearSelection: true)
    }

    private func clearRecursiveSearch(clearSelection: Bool, invalidateRequests: Bool = true) {
        if invalidateRequests {
            cancelRecursiveSearchRequests()
        }

        recursiveSearchResults = []
        recursiveSearchContentMatches = [:]
        recursiveSearchSkippedFileCount = 0
        isShowingRecursiveSearchResults = false

        if clearSelection {
            selectedItems = []
        }
    }

    func recursiveSearchContentMatch(for item: FileItem) -> FileContentMatch? {
        recursiveSearchContentMatches[item.id]
    }

    func recursiveSearchContentDescription(for item: FileItem) -> String? {
        guard let match = recursiveSearchContentMatch(for: item) else {
            return nil
        }

        let relativePath: String
        if let rootURL = fileURL {
            let rootComponents = rootURL.standardizedFileURL.pathComponents
            let itemComponents = item.url.standardizedFileURL.pathComponents
            if itemComponents.starts(with: rootComponents) {
                relativePath = itemComponents
                    .dropFirst(rootComponents.count)
                    .joined(separator: "/")
            } else {
                relativePath = item.url.path
            }
        } else {
            relativePath = item.url.path
        }

        let displayPath = relativePath.isEmpty ? item.name : relativePath
        return "\(displayPath) • Line \(match.lineNumber): \(match.excerpt)"
    }

    private func cancelRecursiveSearchRequests() {
        recursiveSearchTask?.cancel()
        recursiveSearchTask = nil
        recursiveSearchGeneration += 1
        pendingSubtreeSearch = false
        pendingSubtreeSearchContinuations.forEach { $0.resume() }
        pendingSubtreeSearchContinuations = []
        isSearchingSubtree = false
    }

    func markTabsDirty(showingAnyOf directoryURLs: [URL]) {
        let affectedDirectories = Set(directoryURLs.map(\.standardizedFileURL))
        guard !affectedDirectories.isEmpty else {
            return
        }

        var updatedTabs = tabs
        var didChange = false
        for index in updatedTabs.indices where affectedDirectories.contains(updatedTabs[index].currentURL.standardizedFileURL) {
            guard !updatedTabs[index].isDirty else {
                continue
            }
            updatedTabs[index].isDirty = true
            didChange = true
        }

        if didChange {
            tabs = updatedTabs
        }
    }

    func selectForContextMenu(_ item: FileItem) {
        if selectedItems.contains(item) {
            updateFileListSelection { selection, entries in
                selection.focus(item.id, in: entries)
            }
            return
        }

        selectFileListItem(item, commandModifier: false, shiftModifier: false)
    }

    func itemsForDrag(startingFrom item: FileItem) -> [FileItem] {
        if selectedItems.contains(item) {
            if visibleItems.contains(item) {
                updateFileListSelection { selection, entries in
                    selection.focus(item.id, in: entries)
                }
            }
            let orderedItems = orderedSelectedItems
            if !orderedItems.isEmpty {
                return orderedItems
            }

            return selectedItems.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }

        guard visibleItems.contains(item) else {
            selectedItems = [item]
            return [item]
        }

        selectFileListItem(item, commandModifier: false, shiftModifier: false)
        return [item]
    }

    func selectFileListItem(
        _ item: FileItem,
        commandModifier: Bool,
        shiftModifier: Bool
    ) {
        updateFileListSelection { selection, entries in
            if shiftModifier {
                selection.selectRange(to: item.id, in: entries)
            } else if commandModifier {
                selection.toggle(item.id, in: entries)
            } else {
                selection.selectOnly(item.id, in: entries)
            }
        }
    }

    @discardableResult
    func moveFileListFocus(by offset: Int, extendingSelection: Bool) -> FileItem.ID? {
        var focusedID: FileItem.ID?
        updateFileListSelection { selection, entries in
            focusedID = selection.moveFocus(
                by: offset,
                extendingSelection: extendingSelection,
                in: entries
            )
        }
        return focusedID
    }

    @discardableResult
    func moveFileListFocus(toIndex index: Int, extendingSelection: Bool) -> FileItem.ID? {
        var focusedID: FileItem.ID?
        updateFileListSelection { selection, entries in
            focusedID = selection.moveFocus(
                toIndex: index,
                extendingSelection: extendingSelection,
                in: entries
            )
        }
        return focusedID
    }

    func selectAllVisibleItems() {
        updateFileListSelection { selection, entries in
            selection.selectAll(in: entries)
        }
    }

    func selectFileListItems(
        withIDs ids: Set<FileItem.ID>,
        addingToSelection: Bool
    ) {
        updateFileListSelection { selection, entries in
            selection.select(
                ids,
                addingToSelection: addingToSelection,
                in: entries
            )
        }
    }

    @discardableResult
    func selectFileListItemByTypeAhead(_ characters: String, now: Date = Date()) -> FileItem.ID? {
        var focusedID: FileItem.ID?
        updateFileListSelection { selection, entries in
            focusedID = selection.typeAhead(characters, in: entries, now: now)
        }
        return focusedID
    }

    func openFocusedFileListItem() async {
        if let focusedID = focusedFileListItemID,
           let focusedItem = visibleItems.first(where: { $0.id == focusedID }) {
            await open(focusedItem)
            return
        }

        await openSelectedItem()
    }

    func previewFocusedFileListItem() {
        if let focusedID = focusedFileListItemID,
           let focusedItem = visibleItems.first(where: { $0.id == focusedID }) {
            selectFileListItem(focusedItem, commandModifier: false, shiftModifier: false)
        }

        previewSelectedItem()
    }

    @discardableResult
    func copySelectedItemsToPasteboard() -> Int {
        guard isFileBackedLocation else {
            errorMessage = "Copy is unavailable on the Network page."
            return 0
        }

        let targetItems = orderedSelectedItems
        guard !targetItems.isEmpty else {
            errorMessage = "Select one or more items to copy."
            return 0
        }

        errorMessage = nil
        workspaceService.copyFileURLs(targetItems.map(\.url))
        return targetItems.count
    }

    func showPlaceholderError(_ message: String) {
        errorMessage = message
    }

    func copyPath(of item: FileItem) {
        _ = copyTextForContextMenu(clickedItem: item, format: .absolutePath)
    }

    func copyCurrentFolderPath() {
        guard let fileURL else {
            errorMessage = "A filesystem path is unavailable on the Network page."
            return
        }

        errorMessage = nil
        workspaceService.copyText(fileURL.path)
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
        guard isFileBackedLocation else {
            errorMessage = "Copy is unavailable on the Network page."
            return 0
        }

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

        guard workspaceService.open(url: item.url) else {
            errorMessage = WorkspaceError.openFailed(item.url).localizedDescription
            return
        }
    }

    func applicationsAvailableToOpen(_ item: FileItem) -> [ApplicationOption] {
        guard !item.isDirectory else {
            return []
        }

        let cacheKey = Self.openWithCacheKey(for: item)

        if let cachedOptions = applicationOptionsByTypeKey[cacheKey] {
            applicationOptionsKeysInRecencyOrder.removeAll { $0 == cacheKey }
            applicationOptionsKeysInRecencyOrder.append(cacheKey)
            return cachedOptions
        }

        guard applicationOptionsLoadTasksByTypeKey[cacheKey] == nil else {
            return []
        }

        let workspaceService = workspaceService
        let itemURL = item.url
        applicationOptionsLoadTasksByTypeKey[cacheKey] = Task { [weak self] in
            let options = await workspaceService.appsAvailableToOpen(url: itemURL)
            guard !Task.isCancelled,
                  let self else {
                return
            }

            self.applicationOptionsLoadTasksByTypeKey[cacheKey] = nil
            self.storeApplicationOptions(options, for: cacheKey)
        }
        return []
    }

    private func storeApplicationOptions(
        _ options: [ApplicationOption],
        for cacheKey: String
    ) {
        applicationOptionsByTypeKey[cacheKey] = options
        applicationOptionsKeysInRecencyOrder.removeAll { $0 == cacheKey }
        applicationOptionsKeysInRecencyOrder.append(cacheKey)

        while applicationOptionsByTypeKey.count > maximumApplicationOptionsCacheEntryCount,
              let leastRecentlyUsedKey = applicationOptionsKeysInRecencyOrder.first {
            applicationOptionsKeysInRecencyOrder.removeFirst()
            applicationOptionsByTypeKey[leastRecentlyUsedKey] = nil
        }

        applicationOptionsCacheGeneration &+= 1
    }

    nonisolated static func openWithCacheKey(for item: FileItem) -> String {
        if let typeIdentifier = item.typeIdentifier,
           !typeIdentifier.isEmpty {
            return "type:\(typeIdentifier)"
        }

        let pathExtension = item.url.pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if pathExtension.isEmpty {
            return "extension:<none>"
        }

        return "extension:\(pathExtension)"
    }

    func open(_ item: FileItem, withApplication applicationURL: URL) async {
        errorMessage = nil

        do {
            try await workspaceService.open(url: item.url, withApplication: applicationURL)
        } catch {
            errorMessage = Self.userReadableWorkspaceError(for: error)
        }
    }

    func chooseApplicationToOpen(_ item: FileItem) {
        errorMessage = nil
        workspaceService.chooseApplicationAndOpen(url: item.url)
    }

    func calculatedFolderSizeText(for item: FileItem) -> String? {
        guard item.isDirectory else {
            return nil
        }

        let standardizedURL = item.url.standardizedFileURL

        if calculatingFolderSizeURLs.contains(standardizedURL) {
            return "Calculating…"
        }

        if let result = calculatedFolderSizes[standardizedURL] {
            if result.skippedItemCount > 0 {
                return "\(result.formattedSize)*"
            }

            return result.formattedSize
        }

        return nil
    }

    func calculateFolderSizeForContextMenu(clickedItem: FileItem) {
        calculateFolderSize(for: clickedItem)
    }

    func calculateFolderSize(for item: FileItem) {
        guard item.isDirectory else {
            errorMessage = "\(item.displayName) is not a folder."
            return
        }

        let standardizedURL = item.url.standardizedFileURL

        if let cachedSize = folderSizeService.cachedSize(of: item.url) {
            calculatedFolderSizes[standardizedURL] = cachedSize
            return
        }

        folderSizeTasksByURL[standardizedURL]?.cancel()
        calculatingFolderSizeURLs.insert(standardizedURL)
        errorMessage = nil

        folderSizeTasksByURL[standardizedURL] = Task { [weak self] in
            do {
                guard let self else {
                    return
                }

                let result = try await self.folderSizeService.size(of: item.url)
                await MainActor.run {
                    self.calculatingFolderSizeURLs.remove(standardizedURL)
                    self.folderSizeTasksByURL[standardizedURL] = nil
                    self.calculatedFolderSizes[standardizedURL] = result
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.calculatingFolderSizeURLs.remove(standardizedURL)
                    self?.folderSizeTasksByURL[standardizedURL] = nil
                }
            } catch {
                await MainActor.run {
                    self?.calculatingFolderSizeURLs.remove(standardizedURL)
                    self?.folderSizeTasksByURL[standardizedURL] = nil
                    self?.errorMessage = Self.userReadableFolderSizeError(for: error)
                }
            }
        }
    }

    func cancelFolderSizeCalculation(for item: FileItem) {
        let standardizedURL = item.url.standardizedFileURL
        folderSizeTasksByURL[standardizedURL]?.cancel()
        folderSizeTasksByURL[standardizedURL] = nil
        calculatingFolderSizeURLs.remove(standardizedURL)
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
        guard let fileURL else {
            errorMessage = "Reveal in Finder is unavailable on the Network page."
            return
        }

        errorMessage = nil
        workspaceService.revealInFinder(urls: [fileURL])
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
        guard let fileURL else {
            errorMessage = "Go Up is unavailable on the Network page."
            return
        }

        let parentURL = fileURL.deletingLastPathComponent()
        await setDirectory(parentURL)
    }

    func setDirectory(_ url: URL) async {
        await navigate(to: .file(url.standardizedFileURL))
    }

    func navigate(to location: PaneLocation) async {
        let normalizedLocation: PaneLocation
        switch location {
        case .file(let url):
            normalizedLocation = .file(url.standardizedFileURL)
        case .network:
            normalizedLocation = .network
        }

        guard normalizedLocation != currentLocation else {
            if normalizedLocation.isFileBacked {
                await refresh()
            }
            return
        }

        if case .network = normalizedLocation {
            locationBackStack.append(currentLocation)
            locationForwardStack.removeAll()
            publishLegacyHistory()
            applyNetworkLocation()
            return
        }

        guard case .file(let url) = normalizedLocation else {
            return
        }

        guard let snapshot = await snapshotForNavigation(to: url) else {
            return
        }

        locationBackStack.append(currentLocation)
        locationForwardStack.removeAll()
        publishLegacyHistory()
        await applyNavigation(to: url, snapshot: snapshot)
    }

    func goBack() async {
        guard let destination = locationBackStack.last else {
            return
        }

        if case .file(let destinationURL) = destination,
           let snapshot = await snapshotForNavigation(to: destinationURL) {
            locationBackStack.removeLast()
            locationForwardStack.append(currentLocation)
            publishLegacyHistory()
            await applyNavigation(to: destinationURL, snapshot: snapshot)
        } else if case .network = destination {
            locationBackStack.removeLast()
            locationForwardStack.append(currentLocation)
            publishLegacyHistory()
            applyNetworkLocation()
        }
    }

    func goForward() async {
        guard let destination = locationForwardStack.last else {
            return
        }

        if case .file(let destinationURL) = destination,
           let snapshot = await snapshotForNavigation(to: destinationURL) {
            locationForwardStack.removeLast()
            locationBackStack.append(currentLocation)
            publishLegacyHistory()
            await applyNavigation(to: destinationURL, snapshot: snapshot)
        } else if case .network = destination {
            locationForwardStack.removeLast()
            locationBackStack.append(currentLocation)
            publishLegacyHistory()
            applyNetworkLocation()
        }
    }

    private func applyNetworkLocation() {
        invalidatePendingRequests()
        currentDirectoryFingerprint = nil
        visibleItemsTask?.cancel()
        visibleItemsGeneration += 1
        visibleItems = []
        fileListSelection.clear()
        recursiveSearchResults = []
        recursiveSearchContentMatches = [:]
        recursiveSearchSkippedFileCount = 0
        isShowingRecursiveSearchResults = false
        errorMessage = nil
        isLoading = false
        currentLocation = .network
        _ = replaceItemsIfChanged([])
        selectedItems = []
        setActiveTabDirty(false)
        directoryMonitorRefreshTask?.cancel()
        directoryMonitorToken?.cancel()
        directoryMonitorToken = nil
        hasPendingDirectoryMonitorRefresh = false
        hasPendingExplicitRefresh = false
    }

    private func clearFileLocationState() {
        currentDirectoryFingerprint = nil
        visibleItemsTask?.cancel()
        visibleItemsGeneration += 1
        visibleItems = []
        fileListSelection.clear()
        recursiveSearchResults = []
        recursiveSearchContentMatches = [:]
        recursiveSearchSkippedFileCount = 0
        isShowingRecursiveSearchResults = false
        _ = replaceItemsIfChanged([])
        selectedItems = []
        directoryMonitorRefreshTask?.cancel()
        directoryMonitorToken?.cancel()
        directoryMonitorToken = nil
    }

    private func snapshotForNavigation(to url: URL) async -> DirectorySnapshot? {
        let requestTabID = activeTabID
        let generation = nextRequestGeneration()
        var shouldFinishNavigation = true
        activeDirectoryLoadPriority = .userNavigation
        isLoading = true
        errorMessage = nil
        defer {
            if shouldFinishNavigation {
                finishNavigationRequest(generation: generation)
            }
        }

        do {
            let snapshot = try await loadDirectorySnapshot(
                at: url,
                includeFingerprint: false,
                priority: .userInitiated
            )
            guard generation == requestGeneration,
                  activeTabID == requestTabID else {
                return nil
            }

            // Keep navigation marked active until the snapshot has been
            // applied. This prevents a search submitted while the new rows or
            // fingerprint are still being installed from invalidating the
            // navigation request halfway through.
            shouldFinishNavigation = false
            return snapshot
        } catch is CancellationError {
            return nil
        } catch {
            guard generation == requestGeneration,
                  activeTabID == requestTabID else {
                return nil
            }

            errorMessage = Self.userReadableError(for: error, at: url)
            return nil
        }
    }

    private func applyNavigation(to url: URL, snapshot: DirectorySnapshot) async {
        let generation = requestGeneration
        let requestTabID = activeTabID
        defer {
            finishNavigationRequest(generation: generation)
        }
        fileListSelection.clear()
        currentURL = url
        clearRecursiveSearch(clearSelection: false, invalidateRequests: false)
        _ = replaceItemsIfChanged(snapshot.items)
        selectedItems = []
        await waitForVisibleItemsUpdate()
        let fingerprint: DirectoryFingerprint
        if let snapshotFingerprint = snapshot.fingerprint {
            fingerprint = snapshotFingerprint
        } else {
            fingerprint = await Self.directoryFingerprint(
                for: snapshot.items,
                at: url
            )
        }
        guard isCurrentRequest(generation, tabID: requestTabID, url: url) else {
            return
        }
        currentDirectoryFingerprint = fingerprint
        setActiveTabDirty(false)
        restartDirectoryMonitor()
        startMetadataEnrichmentIfNeeded(
            for: snapshot.items,
            generation: requestGeneration,
            tabID: activeTabID,
            directoryURL: url
        )
        directoryNavigationSubject.send(url)
    }

    private func finishNavigationRequest(generation: Int) {
        guard generation == requestGeneration else {
            return
        }

        directoryLoadTask = nil
        activeDirectoryLoadPriority = nil
        isLoading = false
        schedulePendingDirectoryRefreshIfNeeded()
        runPendingSubtreeSearchIfNeeded()
    }

    private func loadDirectorySnapshot(
        at url: URL,
        includeFingerprint: Bool,
        priority: TaskPriority
    ) async throws -> DirectorySnapshot {
        let fileBrowserService = fileBrowserService
        let includeHiddenFiles = includeHiddenFiles
        let task = Task {
            try await fileBrowserService.directorySnapshot(
                at: url,
                includeHiddenFiles: includeHiddenFiles,
                includeFingerprint: includeFingerprint,
                priority: priority
            )
        }
        directoryLoadTask = task

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func scheduleVisibleItemsRecompute(
        debounce: Bool = false,
        invalidateSortedItems: Bool = false,
        preferCachedSortInput: Bool = false
    ) {
        if invalidateSortedItems {
            sortedItemsSourceGeneration += 1
        }
        visibleItemsGeneration += 1
        let generation = visibleItemsGeneration
        let sourceGeneration = sortedItemsSourceGeneration
        visibleItemsTask?.cancel()

        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldSortSourceItems = sortedItemsCacheGeneration != sourceGeneration
        let unsortedSourceItems = isShowingRecursiveSearchResults ? recursiveSearchResults : items
        // A sort-only invalidation can safely reuse the previously sorted
        // array as input. If the source rows changed before the sort setting,
        // however, that cache is more than one generation old and using it
        // would permanently hide the newly loaded rows.
        let canReuseCachedSortInput = preferCachedSortInput &&
            !sortedItemsCache.isEmpty &&
            sortedItemsCacheGeneration == sourceGeneration - 1
        let request = VisibleItemsRequest(
            sourceItems: shouldSortSourceItems
                ? (canReuseCachedSortInput ? sortedItemsCache : unsortedSourceItems)
                : sortedItemsCache,
            filterText: isShowingRecursiveSearchResults || searchMode.isSubtreeSearch || trimmedSearchText.isEmpty
                ? nil
                : trimmedSearchText,
            sortOption: sortOption,
            sortDirection: sortDirection,
            shouldSortSourceItems: shouldSortSourceItems
        )
        let debounceNanoseconds = debounce ? visibleItemsSearchDebounceNanoseconds : 0

        visibleItemsTask = Task(priority: .userInitiated) { [weak self] in
            do {
                if debounceNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                }

                let computation = try await Self.computeVisibleItems(for: request)
                try Task.checkCancellation()

                guard let self,
                      generation == self.visibleItemsGeneration else {
                    return
                }

                self.visibleItemsTask = nil
                if request.shouldSortSourceItems {
                    self.sortedItemsCache = computation.sortedSourceItems
                    self.sortedItemsCacheGeneration = sourceGeneration
                }
                #if DEBUG
                self.visibleItemsRecomputeCount += 1
                PerformanceDiagnostics.shared.recordVisibleItemComputation()
                #endif

                guard computation.visibleItems != self.visibleItems else {
                    return
                }

                #if DEBUG
                self.visibleItemsPublicationCount += 1
                PerformanceDiagnostics.shared.recordVisibleItemPublication()
                #endif
                self.visibleItems = computation.visibleItems
                self.reconcileFileListSelection()
            } catch is CancellationError {
                guard let self,
                      generation == self.visibleItemsGeneration else {
                    return
                }
                self.visibleItemsTask = nil
            } catch {
                guard let self,
                      generation == self.visibleItemsGeneration else {
                    return
                }
                self.visibleItemsTask = nil
            }
        }
    }

    @discardableResult
    private func replaceItemsIfChanged(_ newItems: [FileItem]) -> Bool {
        guard newItems != items else {
            return false
        }

        items = newItems
        return true
    }

    func waitForVisibleItemsUpdate() async {
        let task = visibleItemsTask
        await task?.value
    }

    func waitForMetadataEnrichment() async {
        let task = metadataEnrichmentTask
        await task?.value
    }

    func applyHeaderSort(_ option: FileSortOption) {
        if sortOption == option {
            sortDirection = sortDirection == .ascending ? .descending : .ascending
        } else {
            sortOption = option
            sortDirection = .ascending
        }
    }

    private func startMetadataEnrichmentIfNeeded(
        for sourceItems: [FileItem],
        generation: Int,
        tabID: FilePaneTab.ID,
        directoryURL: URL
    ) {
        metadataEnrichmentTask?.cancel()
        guard sourceItems.contains(where: { !$0.hasExtendedMetadata }) else {
            metadataEnrichmentTask = nil
            return
        }

        metadataEnrichmentTask = Task(priority: .utility) { [weak self] in
            do {
                let enricher = self?.metadataEnricher
                guard let enricher else {
                    return
                }
                let enrichedItems = try await enricher(sourceItems)
                try Task.checkCancellation()

                guard let self,
                      self.isCurrentRequest(generation, tabID: tabID, url: directoryURL) else {
                    return
                }

                let selectedIDs = Set(self.selectedItems.map(\.id))
                let didReplaceItems = self.replaceItemsIfChanged(enrichedItems)
                let enrichedSelection = Set(enrichedItems.filter { selectedIDs.contains($0.id) })
                if enrichedSelection != self.selectedItems {
                    self.selectedItems = enrichedSelection
                }
                if didReplaceItems {
                    await self.waitForVisibleItemsUpdate()
                    #if DEBUG
                    self.metadataEnrichmentPublicationCount += 1
                    #endif
                }
                self.metadataEnrichmentTask = nil
            } catch {
                guard let self,
                      self.isCurrentRequest(generation, tabID: tabID, url: directoryURL) else {
                    return
                }
                self.metadataEnrichmentTask = nil
            }
        }
    }

    nonisolated static func enrichMetadata(
        in sourceItems: [FileItem]
    ) async throws -> [FileItem] {
        let task = Task.detached(priority: .utility) {
            var enrichedItems: [FileItem] = []
            enrichedItems.reserveCapacity(sourceItems.count)

            for (index, item) in sourceItems.enumerated() {
                if index.isMultiple(of: 128) {
                    try Task.checkCancellation()
                }

                guard !item.hasExtendedMetadata else {
                    enrichedItems.append(item)
                    continue
                }

                enrichedItems.append((try? FileItem(url: item.url)) ?? item)
            }

            try Task.checkCancellation()
            return enrichedItems
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func directoryFingerprint(
        for items: [FileItem],
        at directoryURL: URL
    ) async -> DirectoryFingerprint {
        await DirectoryFingerprint.includingDirectoryModificationDate(
            items: items,
            directoryURL: directoryURL
        )
    }

    private nonisolated static func computeVisibleItems(
        for request: VisibleItemsRequest
    ) async throws -> VisibleItemsComputation {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let sortedSourceItems: [FileItem]
            if request.shouldSortSourceItems {
                sortedSourceItems = request.sourceItems.sorted { lhs, rhs in
                    let comparison = compare(lhs, rhs, by: request.sortOption)

                    if comparison != .orderedSame {
                        return request.sortDirection == .ascending
                            ? comparison == .orderedAscending
                            : comparison == .orderedDescending
                    }

                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                try Task.checkCancellation()
            } else {
                sortedSourceItems = request.sourceItems
            }

            let filteredItems: [FileItem]
            if let filterText = request.filterText {
                var matches: [FileItem] = []
                matches.reserveCapacity(sortedSourceItems.count)

                for (index, item) in sortedSourceItems.enumerated() {
                    if index.isMultiple(of: 256) {
                        try Task.checkCancellation()
                    }

                    if item.name.localizedCaseInsensitiveContains(filterText) {
                        matches.append(item)
                    }
                }

                filteredItems = matches
            } else {
                filteredItems = sortedSourceItems
            }

            try Task.checkCancellation()
            return VisibleItemsComputation(
                sortedSourceItems: sortedSourceItems,
                visibleItems: filteredItems
            )
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private var fileListSelectionEntries: [FileListSelectionEntry] {
        visibleItems.map { FileListSelectionEntry(id: $0.id, name: $0.name) }
    }

    private func updateFileListSelection(
        _ update: (inout FileListSelectionController, [FileListSelectionEntry]) -> Void
    ) {
        var selection = fileListSelection
        update(&selection, fileListSelectionEntries)
        fileListSelection = selection
        applyFileListSelectionToSelectedItems()
    }

    private func applyFileListSelectionToSelectedItems() {
        let itemsByID = Dictionary(uniqueKeysWithValues: visibleItems.map { ($0.id, $0) })
        let nextSelection = Set(fileListSelection.orderedSelectionIDs.compactMap { itemsByID[$0] })

        guard nextSelection != selectedItems else {
            return
        }

        isApplyingFileListSelection = true
        selectedItems = nextSelection
        isApplyingFileListSelection = false
    }

    private func synchronizeFileListSelection() {
        var selection = fileListSelection
        selection.synchronize(
            selectedIDs: Set(selectedItems.map(\.id)),
            entries: fileListSelectionEntries
        )
        fileListSelection = selection
    }

    private func reconcileFileListSelection() {
        var selection = fileListSelection
        selection.reconcile(
            entries: fileListSelectionEntries,
            selectedIDs: Set(selectedItems.map(\.id))
        )
        fileListSelection = selection
        applyFileListSelectionToSelectedItems()
    }

    private nonisolated static func compare(
        _ lhs: FileItem,
        _ rhs: FileItem,
        by option: FileSortOption
    ) -> ComparisonResult {
        switch option {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .size:
            return compareValues(lhs.sortSize, rhs.sortSize)
        case .modifiedDate:
            return compareValues(lhs.sortModifiedDate, rhs.sortModifiedDate)
        case .kind:
            return lhs.kindDescription.localizedStandardCompare(rhs.kindDescription)
        }
    }

    private nonisolated static func compareValues<T: Comparable>(
        _ lhs: T,
        _ rhs: T
    ) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }

        if lhs > rhs {
            return .orderedDescending
        }

        return .orderedSame
    }

    private func applyTab(_ tab: FilePaneTab) {
        invalidatePendingRequests()
        currentDirectoryFingerprint = nil
        visibleItemsTask?.cancel()
        visibleItemsGeneration += 1
        visibleItems = []
        fileListSelection.clear()
        activeTabID = tab.id
        recursiveSearchResults = []
        recursiveSearchContentMatches = [:]
        recursiveSearchSkippedFileCount = 0
        isShowingRecursiveSearchResults = false
        errorMessage = nil
        currentLocation = tab.location
        if !replaceItemsIfChanged(tab.items) {
            scheduleVisibleItemsRecompute()
        }
        selectedItems = tab.selectedItems
        touchTabCache(tab.id)
        trimBackgroundTabCaches()
        restartDirectoryMonitor()
    }

    private func restartDirectoryMonitor() {
        directoryMonitorRefreshTask?.cancel()
        directoryMonitorToken?.cancel()
        hasPendingDirectoryMonitorRefresh = false

        guard let url = fileURL else {
            return
        }

        directoryMonitorToken = directoryMonitorService.monitorDirectory(at: url) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleDirectoryMonitorRefresh()
            }
        }
    }

    private static func defaultDirectoryMonitorService() -> any DirectoryMonitorServicing {
        if isRunningUnderXCTest || isRunningForUITests {
            return NoopDirectoryMonitoringService()
        }

        return DirectoryMonitoringService()
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static var isRunningForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    private func scheduleDirectoryMonitorRefresh() {
        directoryMonitorRefreshTask?.cancel()

        let debounceNanoseconds = directoryRefreshDebounceNanoseconds
        directoryMonitorRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await self?.performDirectoryMonitorRefresh()
        }
    }

    private func performDirectoryMonitorRefresh() async {
        guard let requestURL = fileURL else {
            return
        }

        let requestTabID = activeTabID
        let generation = requestGeneration
        let includeHiddenFiles = includeHiddenFiles
        let fileBrowserService = fileBrowserService

        do {
            let snapshot = try await fileBrowserService.directorySnapshot(
                at: requestURL,
                includeHiddenFiles: includeHiddenFiles,
                includeFingerprint: true,
                priority: .utility
            )
            try Task.checkCancellation()

            guard isCurrentRequest(generation, tabID: requestTabID, url: requestURL) else {
                return
            }

            #if DEBUG
            directoryFingerprintCheckCount += 1
            PerformanceDiagnostics.shared.recordDirectoryFingerprintCheck()
            #endif
            guard snapshot.fingerprint != currentDirectoryFingerprint else {
                #if DEBUG
                directoryFingerprintNoOpCount += 1
                PerformanceDiagnostics.shared.recordDirectoryFingerprintNoOp()
                #endif
                return
            }

            await loadCurrentDirectory(
                priority: .monitorRefresh,
                prefetchedSnapshot: snapshot
            )
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentRequest(generation, tabID: requestTabID, url: requestURL) else {
                return
            }
            await loadCurrentDirectory(priority: .monitorRefresh)
        }
    }

    private func schedulePendingDirectoryRefreshIfNeeded() {
        if hasPendingExplicitRefresh {
            hasPendingExplicitRefresh = false
            hasPendingDirectoryMonitorRefresh = false
            Task { [weak self] in
                await self?.loadCurrentDirectory(priority: .explicitRefresh)
            }
            return
        }

        guard hasPendingDirectoryMonitorRefresh else {
            return
        }

        hasPendingDirectoryMonitorRefresh = false
        scheduleDirectoryMonitorRefresh()
    }

    private func saveActiveTabState() {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            return
        }

        var updatedTabs = tabs
        updatedTabs[index].location = currentLocation
        if items.count <= Self.maximumCachedItemsPerTab {
            updatedTabs[index].items = items
            updatedTabs[index].selectedItems = selectedItems
        } else {
            updatedTabs[index].items = []
            updatedTabs[index].selectedItems = []
            updatedTabs[index].isDirty = true
        }

        if updatedTabs != tabs {
            tabs = updatedTabs
        }
        touchTabCache(activeTabID)
        trimBackgroundTabCaches()
    }

    private func touchTabCache(_ id: FilePaneTab.ID) {
        tabCacheRecency.removeAll { $0 == id }
        tabCacheRecency.append(id)
    }

    private func trimBackgroundTabCaches() {
        let cachedBackgroundIDs = tabCacheRecency.filter { id in
            id != activeTabID && tabs.first(where: { $0.id == id })?.items.isEmpty == false
        }
        let excessCount = cachedBackgroundIDs.count - Self.maximumCachedBackgroundTabCount
        guard excessCount > 0 else {
            return
        }

        let evictedIDs = Set(cachedBackgroundIDs.prefix(excessCount))
        var updatedTabs = tabs
        for index in updatedTabs.indices where evictedIDs.contains(updatedTabs[index].id) {
            updatedTabs[index].items = []
            updatedTabs[index].selectedItems = []
            updatedTabs[index].isDirty = true
        }
        tabs = updatedTabs
    }

    private var activeTabIsDirty: Bool {
        tabs.first { $0.id == activeTabID }?.isDirty == true
    }

    private func setActiveTabDirty(_ isDirty: Bool) {
        updateActiveTab { tab in
            tab.isDirty = isDirty
        }
    }

    private func nextRequestGeneration(
        cancelDirectoryMonitorRefresh: Bool = true
    ) -> Int {
        if cancelDirectoryMonitorRefresh {
            directoryMonitorRefreshTask?.cancel()
        }
        directoryLoadTask?.cancel()
        recursiveSearchTask?.cancel()
        recursiveSearchTask = nil
        recursiveSearchGeneration += 1
        isSearchingSubtree = pendingSubtreeSearch
        metadataEnrichmentTask?.cancel()
        activeDirectoryLoadPriority = nil
        requestGeneration += 1
        return requestGeneration
    }

    private func nextRecursiveSearchGeneration() -> Int {
        recursiveSearchTask?.cancel()
        recursiveSearchTask = nil
        recursiveSearchGeneration += 1
        return recursiveSearchGeneration
    }

    private func invalidatePendingRequests() {
        directoryLoadTask?.cancel()
        recursiveSearchTask?.cancel()
        metadataEnrichmentTask?.cancel()
        directoryLoadTask = nil
        recursiveSearchTask = nil
        metadataEnrichmentTask = nil
        recursiveSearchGeneration += 1
        activeDirectoryLoadPriority = nil
        pendingSubtreeSearch = false
        pendingSubtreeSearchContinuations.forEach { $0.resume() }
        pendingSubtreeSearchContinuations = []
        isSearchingSubtree = false
        hasPendingExplicitRefresh = false
        hasPendingDirectoryMonitorRefresh = false
        requestGeneration += 1
        isLoading = false
    }

    private func isCurrentRequest(_ generation: Int, tabID: FilePaneTab.ID, url: URL) -> Bool {
        generation == requestGeneration &&
            activeTabID == tabID &&
            currentLocation.fileURL == url
    }

    private func isCurrentRecursiveSearch(_ generation: Int, tabID: FilePaneTab.ID, url: URL) -> Bool {
        generation == recursiveSearchGeneration &&
            activeTabID == tabID &&
            currentLocation.fileURL == url
    }

    private func updateActiveTab(_ update: (inout FilePaneTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            return
        }

        var updatedTab = tabs[index]
        update(&updatedTab)
        guard updatedTab != tabs[index] else {
            return
        }

        var updatedTabs = tabs
        updatedTabs[index] = updatedTab
        tabs = updatedTabs
    }

    private func boundedTabInsertionIndex(_ index: Int) -> Int {
        min(max(index, 0), tabs.count)
    }

    func sessionState(fileManager: FileManager = .default) -> SessionPaneState {
        saveActiveTabState()

        let sessionTabs = tabs.map { tab in
            SessionTabState(
                id: tab.id,
                location: tab.location
            )
        }

        return SessionPaneState(
            tabs: sessionTabs,
            activeTabID: activeTabID,
            location: currentLocation,
            includeHiddenFiles: includeHiddenFiles,
            sortOption: sortOption,
            sortDirection: sortDirection
        )
    }

    func applySessionState(
        _ state: SessionPaneState,
        fallbackURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        invalidatePendingRequests()
        let restoredTabs = state.tabs.map { tabState in
            switch tabState.location {
            case .network:
                return FilePaneTab(id: tabState.id, location: .network)
            case .file(let url):
                return FilePaneTab(
                    id: tabState.id,
                    currentURL: Self.restorableDirectoryURL(
                        url,
                        fallbackURL: fallbackURL,
                        fileManager: fileManager
                    )
                )
            }
        }
        let safeTabs = restoredTabs.isEmpty
            ? [FilePaneTab(currentURL: fallbackURL)]
            : restoredTabs
        let activeID = safeTabs.contains { $0.id == state.activeTabID }
            ? state.activeTabID
            : safeTabs[0].id
        let activeTab = safeTabs.first { $0.id == activeID } ?? safeTabs[0]

        tabs = safeTabs
        activeTabID = activeID
        currentLocation = activeTab.location
        currentDirectoryFingerprint = nil
        _ = replaceItemsIfChanged([])
        visibleItems = []
        selectedItems = []
        includeHiddenFiles = state.includeHiddenFiles
        searchText = ""
        sortOption = state.sortOption
        sortDirection = state.sortDirection
        recursiveSearchResults = []
        recursiveSearchContentMatches = [:]
        recursiveSearchSkippedFileCount = 0
        isShowingRecursiveSearchResults = false
        backStack = []
        forwardStack = []
        locationBackStack = []
        locationForwardStack = []
        errorMessage = nil
        calculatedFolderSizes = [:]
        calculatingFolderSizeURLs = []
        if currentLocation.isFileBacked {
            restartDirectoryMonitor()
        } else {
            directoryMonitorToken?.cancel()
            directoryMonitorToken = nil
        }
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

    private func invalidateFolderSizeCacheForCurrentDirectory() {
        guard let fileURL else {
            return
        }

        folderSizeService.invalidateDescendants(of: fileURL)
        calculatedFolderSizes = calculatedFolderSizes.filter { url, _ in
            url != fileURL.standardizedFileURL &&
                !url.isDescendant(of: fileURL.standardizedFileURL)
        }
    }

    private func publishLegacyHistory() {
        backStack = locationBackStack.compactMap(\.fileURL)
        forwardStack = locationForwardStack.compactMap(\.fileURL)
    }

    private static func restorableDirectoryURL(
        _ url: URL,
        fallbackURL: URL,
        fileManager: FileManager
    ) -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return fallbackURL
        }

        return url
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

    private static func userReadableFolderSizeError(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return "Could not calculate folder size."
    }
}
