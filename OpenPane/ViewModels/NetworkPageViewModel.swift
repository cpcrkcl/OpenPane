//
//  NetworkPageViewModel.swift
//  OpenPane
//

import Combine
import Foundation

nonisolated enum NetworkConnectionResult: Equatable, Sendable {
    case success([URL])
    case failure(String)
}

@MainActor
final class NetworkPageViewModel: ObservableObject {
    @Published private(set) var discoveredServers: [DiscoveredNetworkServer] = []
    @Published private(set) var savedServers: [NetworkServerBookmark] = []
    @Published private(set) var isBrowsing = false
    @Published private(set) var statusMessage: String?

    private let discoveryService: any NetworkDiscovering
    private let mountService: any NetworkMounting
    private let bookmarkStore: any NetworkServerBookmarkStoring
    private var browseTask: Task<Void, Never>?

    init(
        discoveryService: any NetworkDiscovering = NetworkDiscoveryService(),
        mountService: any NetworkMounting = NetworkMountService(),
        bookmarkStore: any NetworkServerBookmarkStoring = NetworkServerBookmarkStore()
    ) {
        self.discoveryService = discoveryService
        self.mountService = mountService
        self.bookmarkStore = bookmarkStore
        self.savedServers = bookmarkStore.load()
    }

    deinit {
        browseTask?.cancel()
    }

    func startBrowsing() {
        guard browseTask == nil else {
            return
        }

        discoveredServers = []
        statusMessage = nil
        isBrowsing = true
        let stream = discoveryService.browseSMBServices()

        browseTask = Task { @MainActor [weak self] in
            do {
                for try await servers in stream {
                    guard !Task.isCancelled else {
                        return
                    }

                    self?.discoveredServers = servers
                    self?.isBrowsing = false
                }

                self?.isBrowsing = false
                self?.browseTask = nil
            } catch is CancellationError {
                self?.isBrowsing = false
                self?.browseTask = nil
            } catch {
                self?.isBrowsing = false
                self?.browseTask = nil
                self?.statusMessage = error.localizedDescription
            }
        }
    }

    func stopBrowsing() {
        browseTask?.cancel()
        browseTask = nil
        isBrowsing = false
    }

    func refresh() {
        stopBrowsing()
        startBrowsing()
    }

    func connect(
        address: String,
        displayName: String,
        remember: Bool
    ) async -> NetworkConnectionResult {
        statusMessage = nil

        do {
            let normalizedURL = try NetworkServerAddress.normalize(address)
            let mountURLs = try await mountService.mount(serverURL: normalizedURL)

            if remember {
                let bookmark = try NetworkServerBookmark(
                    displayName: displayName,
                    serverURL: normalizedURL
                )
                bookmarkStore.save(bookmark)
                savedServers = bookmarkStore.load()
            }

            return .success(mountURLs)
        } catch is CancellationError {
            return .failure("The connection was cancelled.")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func removeSavedServer(_ server: NetworkServerBookmark) {
        bookmarkStore.remove(server)
        savedServers = bookmarkStore.load()
    }

    func messageAfterMount(with urls: [URL]) {
        if urls.isEmpty {
            statusMessage = "Connected, but macOS did not return a mount point. Refresh Volumes to continue."
        } else {
            statusMessage = nil
        }
    }
}
