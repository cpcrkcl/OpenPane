//
//  NetworkBrowserTests.swift
//  OpenPaneTests
//

import Foundation
import Testing
@testable import OpenPane

@MainActor
struct NetworkBrowserTests {
    @Test func normalizesBareHostsAndRemovesTrailingSlash() throws {
        let url = try NetworkServerAddress.normalize("Server.TS.NET/share/")

        #expect(url.absoluteString == "smb://server.ts.net/share")
    }

    @Test func rejectsCredentialsAndUnsupportedSchemes() {
        #expect(throws: NetworkServerAddressError.credentialsNotAllowed) {
            try NetworkServerAddress.normalize("smb://user:password@server/share")
        }

        #expect(throws: NetworkServerAddressError.unsupportedScheme("ftp")) {
            try NetworkServerAddress.normalize("ftp://server/share")
        }
    }

    @Test func savesOnlyValidatedServerBookmarks() throws {
        let defaults = UserDefaults(suiteName: "OpenPaneNetworkTests-\(UUID().uuidString)")!
        let store = NetworkServerBookmarkStore(
            userDefaults: defaults,
            key: "Bookmarks"
        )
        let bookmark = try NetworkServerBookmark(
            displayName: "Tailnet NAS",
            address: "smb://nas.example.ts.net/media"
        )

        store.save(bookmark)

        #expect(store.load() == [bookmark])
        #expect(store.load().first?.serverURL.user == nil)
        #expect(store.load().first?.serverURL.password == nil)
    }

    @Test func networkPageViewModelMountsAndPersistsARequestedServer() async throws {
        let defaults = UserDefaults(suiteName: "OpenPaneNetworkTests-\(UUID().uuidString)")!
        let bookmarkStore = NetworkServerBookmarkStore(
            userDefaults: defaults,
            key: "Bookmarks"
        )
        let mountURL = URL(filePath: "/Volumes/Tailnet NAS", directoryHint: .isDirectory)
        let mountService = FakeNetworkMountService(result: .success([mountURL]))
        let viewModel = NetworkPageViewModel(
            discoveryService: EmptyNetworkDiscoveryService(),
            mountService: mountService,
            bookmarkStore: bookmarkStore
        )

        let result = await viewModel.connect(
            address: "nas.example.ts.net/media",
            displayName: "Tailnet NAS",
            remember: true
        )

        #expect(result == .success([mountURL]))
        #expect(mountService.requestedURLs == [URL(string: "smb://nas.example.ts.net/media")!])
        #expect(bookmarkStore.load().map(\.displayName) == ["Tailnet NAS"])
    }

    @Test func networkPageViewModelSurfacesMountFailuresAndSupportsMultipleMountPoints() async throws {
        let defaults = UserDefaults(suiteName: "OpenPaneNetworkTests-\(UUID().uuidString)")!
        let bookmarkStore = NetworkServerBookmarkStore(userDefaults: defaults, key: "Bookmarks")
        let mountPoints = [
            URL(filePath: "/Volumes/Share One", directoryHint: .isDirectory),
            URL(filePath: "/Volumes/Share Two", directoryHint: .isDirectory)
        ]
        let multipleMountService = FakeNetworkMountService(result: .success(mountPoints))
        let multipleMountViewModel = NetworkPageViewModel(
            discoveryService: EmptyNetworkDiscoveryService(),
            mountService: multipleMountService,
            bookmarkStore: bookmarkStore
        )

        #expect(await multipleMountViewModel.connect(
            address: "nas.example/share",
            displayName: "NAS",
            remember: false
        ) == .success(mountPoints))

        let failingViewModel = NetworkPageViewModel(
            discoveryService: EmptyNetworkDiscoveryService(),
            mountService: FakeNetworkMountService(result: .failure(NetworkMountError.mountFailed(status: 1))),
            bookmarkStore: bookmarkStore
        )

        #expect(await failingViewModel.connect(
            address: "nas.example/share",
            displayName: "NAS",
            remember: true
        ) == .failure("The network share could not be mounted (status 1)."))
        #expect(bookmarkStore.load().isEmpty)
    }

    @Test func discoveryDeduplicatesServiceIdentityAndTracksAddRemoveSnapshots() async {
        let nas = DiscoveredNetworkServer(name: "NAS")
        let printer = DiscoveredNetworkServer(name: "Printer", serviceType: "_smb._tcp", domain: "local")

        #expect(NetworkDiscoveryService.deduplicatedServers(from: [nas, nas, printer]) == [nas, printer])

        var continuation: AsyncThrowingStream<[DiscoveredNetworkServer], Error>.Continuation!
        let stream = AsyncThrowingStream<[DiscoveredNetworkServer], Error> { streamContinuation in
            continuation = streamContinuation
        }
        let viewModel = NetworkPageViewModel(
            discoveryService: FakeNetworkDiscoveryService(stream: stream)
        )

        viewModel.startBrowsing()
        continuation.yield([nas, printer])
        let didReceiveInitialSnapshot = await waitUntilNetworkState {
            viewModel.discoveredServers == [nas, printer]
        }
        #expect(didReceiveInitialSnapshot)

        continuation.yield([printer])
        let didReceiveRemovalSnapshot = await waitUntilNetworkState {
            viewModel.discoveredServers == [printer]
        }
        #expect(didReceiveRemovalSnapshot)

        viewModel.stopBrowsing()
        continuation.finish()
    }

    @Test func networkSidebarNavigationChangesOnlyTheActivePane() async {
        let leftPane = FilePaneViewModel(currentURL: FileManager.default.homeDirectoryForCurrentUser)
        let rightPane = FilePaneViewModel(currentURL: FileManager.default.temporaryDirectory)
        let dualPane = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await dualPane.navigateActivePane(to: .network)

        #expect(leftPane.currentLocation == .network)
        #expect(rightPane.currentLocation.isFileBacked)

        dualPane.setActivePane(.right)
        await dualPane.navigateActivePane(to: .network)

        #expect(leftPane.currentLocation == .network)
        #expect(rightPane.currentLocation == .network)
    }

    @Test func fileOperationsAreRejectedForNetworkLocations() async {
        let networkPane = FilePaneViewModel(location: .network)
        let localPane = FilePaneViewModel(currentURL: FileManager.default.temporaryDirectory)
        let dualPane = DualPaneViewModel(leftPane: networkPane, rightPane: localPane)

        await dualPane.createFolderInActivePane(named: "Should Not Exist")

        #expect(networkPane.isFileBackedLocation == false)
        #expect(dualPane.errorMessage == "Create folder is unavailable on the Network page.")
    }

    @Test func discoveryErrorAndCancellationStatesAreObservable() async {
        let deniedViewModel = NetworkPageViewModel(
            discoveryService: FailingNetworkDiscoveryService(error: NetworkDiscoveryError.permissionDenied)
        )
        deniedViewModel.startBrowsing()
        let didReceivePermissionError = await waitUntilNetworkState {
            !deniedViewModel.isBrowsing &&
                deniedViewModel.statusMessage?.contains("Local Network permission") == true
        }

        #expect(didReceivePermissionError)

        let stream = AsyncThrowingStream<[DiscoveredNetworkServer], Error> { _ in }
        let cancellableViewModel = NetworkPageViewModel(
            discoveryService: FakeNetworkDiscoveryService(stream: stream)
        )
        cancellableViewModel.startBrowsing()
        #expect(cancellableViewModel.isBrowsing)
        cancellableViewModel.stopBrowsing()
        #expect(!cancellableViewModel.isBrowsing)
    }

    @Test func paneLocationRoundTripsNetworkDestination() throws {
        let encoded = try JSONEncoder().encode(PaneLocation.network)
        let decoded = try JSONDecoder().decode(PaneLocation.self, from: encoded)

        #expect(decoded == .network)
    }

    @Test func sessionStatePreservesNetworkAndReadsLegacyURLState() throws {
        let tabID = UUID()
        let networkState = SessionPaneState(
            tabs: [SessionTabState(id: tabID, location: .network)],
            activeTabID: tabID,
            location: .network,
            includeHiddenFiles: false,
            sortOption: .name,
            sortDirection: .ascending
        )
        let roundTripped = try JSONDecoder().decode(
            SessionPaneState.self,
            from: JSONEncoder().encode(networkState)
        )

        #expect(roundTripped.location == .network)
        #expect(roundTripped.tabs.first?.location == .network)

        let legacyJSON: [String: Any] = [
            "tabs": [[
                "id": tabID.uuidString,
                "currentURL": URL(filePath: "/tmp", directoryHint: .isDirectory).absoluteString
            ]],
            "activeTabID": tabID.uuidString,
            "currentURL": URL(filePath: "/tmp", directoryHint: .isDirectory).absoluteString,
            "includeHiddenFiles": false,
            "sortOption": "name",
            "sortDirection": "ascending",
            "directoriesFirst": true
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        let restoredLegacy = try JSONDecoder().decode(SessionPaneState.self, from: legacyData)

        #expect(restoredLegacy.location == .file(URL(filePath: "/tmp", directoryHint: .isDirectory)))
        #expect(restoredLegacy.tabs.first?.location == restoredLegacy.location)
    }

    @Test func filePaneCanNavigateToNetworkAndBack() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneNetworkNavigation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let viewModel = FilePaneViewModel(
            currentURL: rootURL,
            fileBrowserService: FileBrowserService()
        )
        await viewModel.loadCurrentDirectory()
        await viewModel.navigate(to: .network)

        #expect(viewModel.currentLocation == .network)
        #expect(viewModel.visibleItems.isEmpty)

        await viewModel.goBack()

        #expect(viewModel.currentLocation == .file(rootURL))
        #expect(viewModel.currentURL == rootURL)
    }
}

private struct EmptyNetworkDiscoveryService: NetworkDiscovering {
    func browseSMBServices() -> AsyncThrowingStream<[DiscoveredNetworkServer], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }
}

private struct FailingNetworkDiscoveryService: NetworkDiscovering {
    let error: NetworkDiscoveryError

    func browseSMBServices() -> AsyncThrowingStream<[DiscoveredNetworkServer], Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

@MainActor
private func waitUntilNetworkState(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    intervalNanoseconds: UInt64 = 10_000_000,
    condition: () -> Bool
) async -> Bool {
    var remainingNanoseconds = timeoutNanoseconds

    while !condition() {
        guard remainingNanoseconds > 0 else {
            return false
        }

        let sleepNanoseconds = min(intervalNanoseconds, remainingNanoseconds)
        try? await Task.sleep(nanoseconds: sleepNanoseconds)
        remainingNanoseconds -= sleepNanoseconds
    }

    return true
}
