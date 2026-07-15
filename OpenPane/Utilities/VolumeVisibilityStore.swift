//
//  VolumeVisibilityStore.swift
//  OpenPane
//
//  Created by Codex on 7/11/26.
//

import Combine
import Foundation

@MainActor
final class VolumeVisibilityStore: ObservableObject {
    nonisolated static let defaultUserDefaultsKey = "OpenPaneHiddenVolumeIdentifiers"

    @Published private(set) var hiddenVolumeIdentifiers: Set<String>

    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = VolumeVisibilityStore.defaultUserDefaultsKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.hiddenVolumeIdentifiers = Set(userDefaults.stringArray(forKey: key) ?? [])
    }

    func isVisible(_ volume: MountedVolume) -> Bool {
        isVisible(identifier: volume.persistentIdentifier)
    }

    func isHidden(_ volume: MountedVolume) -> Bool {
        !isVisible(volume)
    }

    func isVisible(identifier: String) -> Bool {
        !hiddenVolumeIdentifiers.contains(identifier)
    }

    func isHidden(identifier: String) -> Bool {
        hiddenVolumeIdentifiers.contains(identifier)
    }

    func visibleVolumes(from volumes: [MountedVolume]) -> [MountedVolume] {
        volumes.filter(isVisible)
    }

    func hiddenVolumes(from volumes: [MountedVolume]) -> [MountedVolume] {
        volumes.filter(isHidden)
    }

    func setVisible(_ visible: Bool, for volume: MountedVolume) {
        setVisible(visible, forIdentifier: volume.persistentIdentifier)
    }

    func setVisible(_ visible: Bool, forIdentifier identifier: String) {
        let shouldBeHidden = !visible
        let isHidden = hiddenVolumeIdentifiers.contains(identifier)
        guard isHidden != shouldBeHidden else {
            return
        }

        if shouldBeHidden {
            hiddenVolumeIdentifiers.insert(identifier)
        } else {
            hiddenVolumeIdentifiers.remove(identifier)
        }

        userDefaults.set(hiddenVolumeIdentifiers.sorted(), forKey: key)
    }

    func hide(_ volume: MountedVolume) {
        setVisible(false, for: volume)
    }

    func show(_ volume: MountedVolume) {
        setVisible(true, for: volume)
    }

    func hide(identifier: String) {
        setVisible(false, forIdentifier: identifier)
    }

    func show(identifier: String) {
        setVisible(true, forIdentifier: identifier)
    }
}
