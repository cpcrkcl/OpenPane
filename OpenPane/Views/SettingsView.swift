//
//  SettingsView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var keyboardShortcutStore: KeyboardShortcutStore
    @ObservedObject var volumeVisibilityStore: VolumeVisibilityStore
    @StateObject private var volumeViewModel: SidebarViewModel
    @AppStorage(DefaultFileDropAction.userDefaultsKey) private var defaultFileDropActionRawValue = DefaultFileDropAction.copy.rawValue
    @AppStorage(PaneLinkMode.userDefaultsKey) private var paneLinkModeRawValue = PaneLinkMode.off.rawValue
    @State private var recordingAction: OpenPaneShortcutAction?

    init(volumeVisibilityStore: VolumeVisibilityStore, favoriteStore: FavoriteStore) {
        self.volumeVisibilityStore = volumeVisibilityStore
        _volumeViewModel = StateObject(
            wrappedValue: SidebarViewModel(
                volumeVisibilityStore: volumeVisibilityStore,
                favoriteStore: favoriteStore
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            settingsShortcutNote
            fileDropSection
            paneLinkSection
            favoritesSection
            volumeVisibilitySection
            shortcutsSection
        }
        .padding(24)
        .frame(width: 540, height: 700, alignment: .topLeading)
        .background(CatppuccinMochaTheme.appBackground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("OpenPane Settings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)

                Text("Click a shortcut, then press the new key combination.")
                    .font(.system(size: 12))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            }

            Spacer()

            Button {
                keyboardShortcutStore.resetToDefaults()
                recordingAction = nil
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
    }

    private var settingsShortcutNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape")
                .foregroundStyle(CatppuccinMochaTheme.accentSecondary)
                .frame(width: 22)

            Text("Open Settings")
                .font(.system(size: 13))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)

            Spacer()

            shortcutCapsule("⌘,")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            CatppuccinMochaTheme.mantle,
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(CatppuccinMochaTheme.mutedText)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(OpenPaneShortcutAction.allCases) { action in
                        ShortcutRowView(
                            action: action,
                            shortcut: keyboardShortcutStore.shortcut(for: action),
                            isRecording: recordingAction == action
                        ) {
                            recordingAction = action
                        } onCapture: { shortcut in
                            keyboardShortcutStore.setShortcut(shortcut, for: action)
                            recordingAction = nil
                        } onCancel: {
                            recordingAction = nil
                        }

                        if action.id != OpenPaneShortcutAction.allCases.last?.id {
                            Rectangle()
                                .fill(CatppuccinMochaTheme.surface0)
                                .frame(height: CatppuccinMochaTheme.hairlineBorderWidth)
                        }
                    }
                }
                .background(CatppuccinMochaTheme.mantle)
            }
            .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                    .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
            }
        }
    }

    private var fileDropSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Default drop action")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)

                Text("Applies to external and same-pane drops. Cross-pane drags move items.")
                    .font(.system(size: 11))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            }

            Spacer()

            Picker("Default drop action", selection: $defaultFileDropActionRawValue) {
                ForEach(DefaultFileDropAction.allCases) { action in
                    Text(action.title).tag(action.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            CatppuccinMochaTheme.mantle,
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }

    private var favoritesSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Favorites")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)

                Text("Restore the built-in Home, Desktop, Documents, Downloads, and Applications favorites.")
                    .font(.system(size: 11))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            }

            Spacer()

            Button("Reset to Defaults") {
                volumeViewModel.resetFavoritesToDefaults()
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            CatppuccinMochaTheme.mantle,
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }

    private var paneLinkSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Linked panes")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)

                Text("Choose which pane navigation should keep the other pane in sync.")
                    .font(.system(size: 11))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            }

            Spacer()

            Picker("Linked panes", selection: $paneLinkModeRawValue) {
                ForEach(PaneLinkMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            CatppuccinMochaTheme.mantle,
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }

    private var volumeVisibilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Visible Volumes")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(CatppuccinMochaTheme.mutedText)

            if volumeViewModel.allMountedVolumes.isEmpty {
                Text("No mounted volumes are available.")
                    .font(.system(size: 12))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            } else {
                VolumeVisibilityPickerView(
                    visibilityStore: volumeVisibilityStore,
                    volumes: volumeViewModel.allMountedVolumes
                )
                .frame(height: 120)
            }
        }
    }

    private func shortcutCapsule(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                CatppuccinMochaTheme.surface0.opacity(0.86),
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                    .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
            }
    }
}

private struct ShortcutRowView: View {
    let action: OpenPaneShortcutAction
    let shortcut: OpenPaneKeyboardShortcut
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onCapture: (OpenPaneKeyboardShortcut) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(action.title)
                .font(.system(size: 13))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)

            Spacer()

            Button(action: onStartRecording) {
                Text(isRecording ? "Press keys" : shortcut.displayText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isRecording ? CatppuccinMochaTheme.crust : CatppuccinMochaTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(minWidth: 88)
                    .background(
                        isRecording ? CatppuccinMochaTheme.accent : CatppuccinMochaTheme.surface0.opacity(0.86),
                        in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                            .stroke(
                                isRecording ? CatppuccinMochaTheme.accentSecondary.opacity(0.75) : CatppuccinMochaTheme.surface1,
                                lineWidth: CatppuccinMochaTheme.hairlineBorderWidth
                            )
                    }
            }
            .buttonStyle(.plain)
            .background {
                ShortcutCaptureView(
                    isRecording: isRecording,
                    onCapture: onCapture,
                    onCancel: onCancel
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let isRecording: Bool
    let onCapture: (OpenPaneKeyboardShortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel

        guard isRecording else {
            return
        }

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class ShortcutCaptureNSView: NSView {
    var isRecording = false
    var onCapture: (OpenPaneKeyboardShortcut) -> Void = { _ in }
    var onCancel: () -> Void = {}

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            onCancel()
            return
        }

        guard let shortcut = OpenPaneKeyboardShortcut(event: event) else {
            return
        }

        onCapture(shortcut)
    }
}

private extension OpenPaneKeyboardShortcut {
    init?(event: NSEvent) {
        guard let key = ShortcutKey(event: event) else {
            return nil
        }

        let flags = event.modifierFlags
        self.init(
            key: key,
            usesCommand: flags.contains(.command),
            usesShift: flags.contains(.shift),
            usesOption: flags.contains(.option),
            usesControl: flags.contains(.control)
        )
    }
}

private extension ShortcutKey {
    init?(event: NSEvent) {
        switch event.keyCode {
        case 36:
            self.init(rawValue: "return")
        case 51, 117:
            self.init(rawValue: "delete")
        case 126:
            self.init(rawValue: "upArrow")
        case 49:
            self.init(rawValue: "space")
        default:
            guard let character = event.charactersIgnoringModifiers?.first,
                  !String(character).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            self.init(rawValue: String(character).lowercased())
        }
    }
}
