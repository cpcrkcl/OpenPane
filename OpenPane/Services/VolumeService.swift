//
//  VolumeService.swift
//  OpenPane
//
//  Created by Codex on 7/3/26.
//

import AppKit
import Foundation

protocol VolumeMonitorToken: AnyObject, Sendable {
    nonisolated func cancel()
}

@MainActor
protocol VolumeServicing: Sendable {
    func mountedVolumes() -> [MountedVolume]
    func startMonitoring(onChange: @escaping @MainActor @Sendable () -> Void) -> any VolumeMonitorToken
}

@MainActor
final class VolumeService: VolumeServicing {
    private let fileManager: FileManager
    private let workspace: NSWorkspace

    init(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared
    ) {
        self.fileManager = fileManager
        self.workspace = workspace
    }

    func mountedVolumes() -> [MountedVolume] {
        let resourceKeys: [URLResourceKey] = [
            .localizedNameKey,
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]

        let volumeURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: resourceKeys,
            options: []
        ) ?? []

        return volumeURLs
            .map { volumeURL in
                volume(for: volumeURL, resourceKeys: Set(resourceKeys))
            }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    func startMonitoring(onChange: @escaping @MainActor @Sendable () -> Void) -> any VolumeMonitorToken {
        WorkspaceVolumeMonitorToken(
            notificationCenter: workspace.notificationCenter,
            onChange: onChange
        )
    }

    private func volume(for url: URL, resourceKeys: Set<URLResourceKey>) -> MountedVolume {
        let values = try? url.resourceValues(forKeys: resourceKeys)
        let displayName = values?.localizedName ??
            values?.volumeName ??
            url.openPaneDisplayName

        return MountedVolume(
            displayName: displayName.isEmpty ? url.path : displayName,
            url: url,
            icon: Self.resizedIconCopy(workspace.icon(forFile: url.path)),
            isRemovable: values?.volumeIsRemovable ?? false,
            isEjectable: values?.volumeIsEjectable ?? false,
            totalCapacity: values?.volumeTotalCapacity.map(Int64.init),
            availableCapacity: values?.volumeAvailableCapacity.map(Int64.init)
        )
    }

    private static func resizedIconCopy(_ image: NSImage) -> NSImage {
        let copiedImage = (image.copy() as? NSImage) ?? image
        copiedImage.size = NSSize(width: 16, height: 16)
        return copiedImage
    }
}

private final class WorkspaceVolumeMonitorToken: VolumeMonitorToken, @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter,
        onChange: @escaping @MainActor @Sendable () -> Void
    ) {
        self.notificationCenter = notificationCenter
        let notifications: [NSNotification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.willUnmountNotification
        ]

        observers = notifications.map { notificationName in
            notificationCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    onChange()
                }
            }
        }
    }

    nonisolated func cancel() {
        let observersToRemove = lock.withLock {
            let observersToRemove = observers
            observers.removeAll()
            return observersToRemove
        }

        observersToRemove.forEach(notificationCenter.removeObserver)
    }
}
