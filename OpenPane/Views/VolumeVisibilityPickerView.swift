//
//  VolumeVisibilityPickerView.swift
//  OpenPane
//
//  Created by Codex on 7/11/26.
//

import SwiftUI

struct VolumeVisibilityPickerView: View {
    @ObservedObject var visibilityStore: VolumeVisibilityStore
    let volumes: [MountedVolume]

    var body: some View {
        List(volumes) { volume in
            Toggle(isOn: visibilityBinding(for: volume)) {
                HStack(spacing: 8) {
                    if let icon = volume.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: volume.isEjectable || volume.isRemovable ? "externaldrive" : "internaldrive")
                            .frame(width: 16)
                    }

                    Text(volume.displayName)
                        .lineLimit(1)
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("volume-visibility-\(volume.persistentIdentifier)")
        }
        .frame(minWidth: 260, minHeight: 180)
        .accessibilityIdentifier("volume-visibility-picker")
    }

    private func visibilityBinding(for volume: MountedVolume) -> Binding<Bool> {
        Binding(
            get: { visibilityStore.isVisible(volume) },
            set: { visibilityStore.setVisible($0, for: volume) }
        )
    }
}
