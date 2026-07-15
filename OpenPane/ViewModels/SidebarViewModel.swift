//
//  SidebarViewModel.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/6/26.
//

import Combine
import Foundation

@MainActor
final class SidebarViewModel: ObservableObject {
    @Published private(set) var favoriteLocations: [FavoriteLocation]
    @Published private(set) var allMountedVolumes: [MountedVolume]
    @Published private(set) var visibleMountedVolumes: [MountedVolume]

    var mountedVolumes: [MountedVolume] {
        visibleMountedVolumes
    }

    private let volumeService: any VolumeServicing
    let volumeVisibilityStore: VolumeVisibilityStore
    let favoriteStore: FavoriteStore
    private var volumeMonitorToken: (any VolumeMonitorToken)?
    private var volumeVisibilityCancellable: AnyCancellable?
    private var favoritesCancellable: AnyCancellable?

    init(
        favoriteLocations: [FavoriteLocation]? = nil,
        volumeService: (any VolumeServicing)? = nil,
        volumeVisibilityStore: VolumeVisibilityStore? = nil,
        favoriteStore: FavoriteStore? = nil
    ) {
        let resolvedVolumeService = volumeService ?? VolumeService()
        let resolvedVisibilityStore = volumeVisibilityStore ?? VolumeVisibilityStore()
        let resolvedFavoriteStore = favoriteStore ?? FavoriteStore()
        let shouldLoadVolumes = volumeService != nil || !(Self.isRunningUnderXCTest || Self.isRunningForUITests)

        if let favoriteLocations {
            resolvedFavoriteStore.replace(
                with: favoriteLocations.compactMap { location in
                    try? FavoriteBookmark(
                        id: location.id,
                        name: location.name,
                        url: location.url,
                        systemImage: location.systemImage
                    )
                }
            )
        } else if !Self.isRunningUnderXCTest && !Self.isRunningForUITests {
            resolvedFavoriteStore.seedDefaultsIfNeeded()
        }

        let initialVolumes = shouldLoadVolumes ? resolvedVolumeService.mountedVolumes() : []
        self.favoriteLocations = favoriteLocations ?? resolvedFavoriteStore.favoriteLocations
        self.volumeService = resolvedVolumeService
        self.volumeVisibilityStore = resolvedVisibilityStore
        self.favoriteStore = resolvedFavoriteStore
        self.allMountedVolumes = initialVolumes
        self.visibleMountedVolumes = resolvedVisibilityStore.visibleVolumes(from: initialVolumes)
        self.volumeMonitorToken = nil
        self.volumeVisibilityCancellable = nil
        self.favoritesCancellable = nil

        self.volumeVisibilityCancellable = resolvedVisibilityStore.$hiddenVolumeIdentifiers.sink { [weak self] hiddenIdentifiers in
            self?.updateVisibleMountedVolumes(hiddenIdentifiers: hiddenIdentifiers)
        }

        self.favoritesCancellable = resolvedFavoriteStore.$bookmarks.sink { [weak self] _ in
            self?.favoriteLocations = resolvedFavoriteStore.favoriteLocations
        }

        if shouldLoadVolumes {
            self.volumeMonitorToken = resolvedVolumeService.startMonitoring { [weak self] in
                self?.refreshVolumes()
            }
        }
    }

    deinit {
        volumeMonitorToken?.cancel()
    }

    func refreshVolumes() {
        allMountedVolumes = volumeService.mountedVolumes()
        updateVisibleMountedVolumes()
    }

    func setVolumeVisible(_ visible: Bool, for volume: MountedVolume) {
        volumeVisibilityStore.setVisible(visible, for: volume)
    }

    func hideVolume(_ volume: MountedVolume) {
        setVolumeVisible(false, for: volume)
    }

    func showVolume(_ volume: MountedVolume) {
        setVolumeVisible(true, for: volume)
    }

    func isVolumeVisible(_ volume: MountedVolume) -> Bool {
        volumeVisibilityStore.isVisible(volume)
    }

    func addFavorite(name: String, url: URL, systemImage: String = "folder") throws {
        _ = try favoriteStore.add(name: name, url: url, systemImage: systemImage)
    }

    func removeFavorite(id: String) {
        favoriteStore.remove(id: id)
    }

    func renameFavorite(id: String, to name: String) {
        favoriteStore.rename(id: id, to: name)
    }

    func reorderFavorites(from source: IndexSet, to destination: Int) {
        favoriteStore.reorder(from: source, to: destination)
    }

    func resetFavoritesToDefaults() {
        favoriteStore.resetToDefaults()
    }

    func containsFavorite(url: URL) -> Bool {
        favoriteStore.contains(url: url)
    }

    private func updateVisibleMountedVolumes(hiddenIdentifiers: Set<String>? = nil) {
        let hiddenIdentifiers = hiddenIdentifiers ?? volumeVisibilityStore.hiddenVolumeIdentifiers
        visibleMountedVolumes = allMountedVolumes.filter {
            !hiddenIdentifiers.contains($0.persistentIdentifier)
        }
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static var isRunningForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }
}
