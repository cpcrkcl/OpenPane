//
//  SidebarViewModelTests.swift
//  OpenPaneTests
//
//  Created by Christopher Rego on 6/6/26.
//

import Foundation
import Testing
@testable import OpenPane

@MainActor
struct SidebarViewModelTests {
    @Test func defaultFavoritesIncludeStandardLocations() {
        let favoriteStore = FavoriteStore(userDefaults: makeUserDefaults())
        favoriteStore.seedDefaultsIfEmpty()
        let viewModel = SidebarViewModel(favoriteStore: favoriteStore)

        #expect(viewModel.favoriteLocations.map(\.name) == [
            "Home",
            "Desktop",
            "Documents",
            "Downloads",
            "Applications"
        ])
    }

    @Test func acceptsInjectedFavoriteLocations() {
        let favoriteLocation = FavoriteLocation(
            name: "Projects",
            url: URL(filePath: "/Projects", directoryHint: .isDirectory),
            systemImage: "folder"
        )

        let viewModel = SidebarViewModel(favoriteLocations: [favoriteLocation])

        #expect(viewModel.favoriteLocations == [favoriteLocation])
    }

    @Test func listsInjectedMockVolumes() {
        let volume = makeVolume(named: "External", path: "/Volumes/External")
        let volumeService = MockVolumeService(volumes: [volume])

        let viewModel = SidebarViewModel(
            volumeService: volumeService,
            volumeVisibilityStore: VolumeVisibilityStore(userDefaults: makeUserDefaults(), key: "HiddenVolumes")
        )

        #expect(viewModel.allMountedVolumes == [volume])
        #expect(viewModel.visibleMountedVolumes == [volume])
        #expect(viewModel.mountedVolumes == [volume])
        #expect(viewModel.mountedVolumes.first?.detailText == nil)
    }

    @Test func refreshVolumesUsesLatestServiceValues() {
        let firstVolume = makeVolume(
            named: "Disk Image",
            path: "/Volumes/Disk Image",
            totalCapacity: 100,
            availableCapacity: 40
        )
        let secondVolume = makeVolume(named: "Network Share", path: "/Volumes/Share")
        let volumeService = MockVolumeService(volumes: [firstVolume])
        let viewModel = SidebarViewModel(
            volumeService: volumeService,
            volumeVisibilityStore: VolumeVisibilityStore(userDefaults: makeUserDefaults(), key: "HiddenVolumes")
        )

        volumeService.volumes = [secondVolume]
        viewModel.refreshVolumes()

        #expect(viewModel.allMountedVolumes == [secondVolume])
        #expect(viewModel.visibleMountedVolumes == [secondVolume])
        #expect(viewModel.mountedVolumes == [secondVolume])
    }

    @Test func hidesAndShowsVolumesThroughTheVisibilityStore() {
        let userDefaults = makeUserDefaults()
        let key = "HiddenVolumes"
        let hiddenVolume = makeVolume(
            named: "External",
            path: "/Volumes/External",
            persistentIdentifier: "volume:external"
        )
        let visibleVolume = makeVolume(
            named: "Backup",
            path: "/Volumes/Backup",
            persistentIdentifier: "volume:backup"
        )
        let store = VolumeVisibilityStore(userDefaults: userDefaults, key: key)
        let volumeService = MockVolumeService(volumes: [hiddenVolume, visibleVolume])
        let viewModel = SidebarViewModel(
            volumeService: volumeService,
            volumeVisibilityStore: store
        )

        viewModel.hideVolume(hiddenVolume)

        #expect(viewModel.allMountedVolumes == [hiddenVolume, visibleVolume])
        #expect(viewModel.visibleMountedVolumes == [visibleVolume])
        #expect(viewModel.mountedVolumes == [visibleVolume])
        #expect(store.isHidden(hiddenVolume))
        #expect(userDefaults.stringArray(forKey: key) == [hiddenVolume.persistentIdentifier])

        let restoredStore = VolumeVisibilityStore(userDefaults: userDefaults, key: key)
        #expect(restoredStore.hiddenVolumeIdentifiers == Set([hiddenVolume.persistentIdentifier]))
        #expect(restoredStore.isHidden(hiddenVolume))

        viewModel.showVolume(hiddenVolume)

        #expect(viewModel.visibleMountedVolumes == [hiddenVolume, visibleVolume])
        #expect(store.isVisible(hiddenVolume))
        #expect(userDefaults.stringArray(forKey: key) == [])
    }

    @Test func hiddenVolumeRemainsHiddenWhenItsNameAndMountPathChange() {
        let userDefaults = makeUserDefaults()
        let key = "HiddenVolumes"
        let originalVolume = makeVolume(
            named: "External",
            path: "/Volumes/External",
            persistentIdentifier: "volume:external"
        )
        let remountedVolume = makeVolume(
            named: "Renamed External",
            path: "/Volumes/Renamed External",
            persistentIdentifier: originalVolume.persistentIdentifier
        )
        let store = VolumeVisibilityStore(userDefaults: userDefaults, key: key)

        store.hide(originalVolume)

        #expect(store.isHidden(remountedVolume))
        #expect(store.hiddenVolumes(from: [remountedVolume]) == [remountedVolume])
        #expect(store.visibleVolumes(from: [remountedVolume]).isEmpty)
    }

    @Test func monitoringRefreshesAllAndVisibleVolumesEvenWhenAVolumeIsHidden() {
        let store = VolumeVisibilityStore(userDefaults: makeUserDefaults(), key: "HiddenVolumes")
        let hiddenVolume = makeVolume(
            named: "External",
            path: "/Volumes/External",
            persistentIdentifier: "volume:external"
        )
        let newlyMountedVolume = makeVolume(
            named: "New Disk",
            path: "/Volumes/New Disk",
            persistentIdentifier: "volume:new-disk"
        )
        let volumeService = MockVolumeService(volumes: [hiddenVolume])
        let viewModel = SidebarViewModel(
            volumeService: volumeService,
            volumeVisibilityStore: store
        )
        viewModel.hideVolume(hiddenVolume)

        volumeService.volumes = [hiddenVolume, newlyMountedVolume]
        volumeService.notifyChange()

        #expect(viewModel.allMountedVolumes == [hiddenVolume, newlyMountedVolume])
        #expect(viewModel.visibleMountedVolumes == [newlyMountedVolume])
    }

    @Test func persistentIdentifierUsesVolumeIdentifierWhenAvailable() {
        let url = URL(filePath: "/", directoryHint: .isDirectory)
        let resourceValues = try? url.resourceValues(forKeys: [.volumeUUIDStringKey])

        #expect(resourceValues?.volumeUUIDString != nil)
        #expect(MountedVolume.persistentIdentifier(for: url, resourceValues: resourceValues).hasPrefix("uuid:"))
    }

    @Test func persistentIdentifierFallsBackToStandardizedPath() {
        let url = URL(filePath: "/tmp/OpenPaneMissing-\(UUID())/../Volume", directoryHint: .isDirectory)
        let expectedIdentifier = "path:\(url.standardizedFileURL.path)"

        #expect(MountedVolume.persistentIdentifier(for: url, resourceValues: URLResourceValues()) == expectedIdentifier)
    }

    private func makeVolume(
        named name: String,
        path: String,
        totalCapacity: Int64? = nil,
        availableCapacity: Int64? = nil,
        persistentIdentifier: String? = nil
    ) -> MountedVolume {
        MountedVolume(
            displayName: name,
            url: URL(filePath: path, directoryHint: .isDirectory),
            icon: nil,
            isRemovable: true,
            isEjectable: true,
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity,
            persistentIdentifier: persistentIdentifier
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "OpenPaneVolumeTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}

@MainActor
private final class MockVolumeService: VolumeServicing, @unchecked Sendable {
    var volumes: [MountedVolume]
    private var onChange: (@MainActor @Sendable () -> Void)?

    init(volumes: [MountedVolume]) {
        self.volumes = volumes
    }

    func mountedVolumes() -> [MountedVolume] {
        volumes
    }

    func startMonitoring(onChange: @escaping @MainActor @Sendable () -> Void) -> any VolumeMonitorToken {
        self.onChange = onChange
        return MockVolumeMonitorToken()
    }

    func notifyChange() {
        onChange?()
    }
}

private final class MockVolumeMonitorToken: VolumeMonitorToken {
    nonisolated func cancel() {}
}
