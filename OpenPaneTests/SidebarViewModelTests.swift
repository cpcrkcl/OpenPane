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
        let viewModel = SidebarViewModel()

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
        let volume = MountedVolume(
            displayName: "External",
            url: URL(filePath: "/Volumes/External", directoryHint: .isDirectory),
            icon: nil,
            isRemovable: true,
            isEjectable: true,
            totalCapacity: nil,
            availableCapacity: nil
        )
        let volumeService = MockVolumeService(volumes: [volume])

        let viewModel = SidebarViewModel(volumeService: volumeService)

        #expect(viewModel.mountedVolumes == [volume])
        #expect(viewModel.mountedVolumes.first?.detailText == nil)
    }

    @Test func refreshVolumesUsesLatestServiceValues() {
        let firstVolume = MountedVolume(
            displayName: "Disk Image",
            url: URL(filePath: "/Volumes/Disk Image", directoryHint: .isDirectory),
            icon: nil,
            isRemovable: true,
            isEjectable: true,
            totalCapacity: 100,
            availableCapacity: 40
        )
        let secondVolume = MountedVolume(
            displayName: "Network Share",
            url: URL(filePath: "/Volumes/Share", directoryHint: .isDirectory),
            icon: nil,
            isRemovable: false,
            isEjectable: true,
            totalCapacity: nil,
            availableCapacity: nil
        )
        let volumeService = MockVolumeService(volumes: [firstVolume])
        let viewModel = SidebarViewModel(volumeService: volumeService)

        volumeService.volumes = [secondVolume]
        viewModel.refreshVolumes()

        #expect(viewModel.mountedVolumes == [secondVolume])
    }
}

@MainActor
private final class MockVolumeService: VolumeServicing, @unchecked Sendable {
    var volumes: [MountedVolume]

    init(volumes: [MountedVolume]) {
        self.volumes = volumes
    }

    func mountedVolumes() -> [MountedVolume] {
        volumes
    }

    func startMonitoring(onChange: @escaping @MainActor @Sendable () -> Void) -> any VolumeMonitorToken {
        MockVolumeMonitorToken()
    }
}

private final class MockVolumeMonitorToken: VolumeMonitorToken {
    nonisolated func cancel() {}
}
