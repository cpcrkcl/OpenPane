//
//  SettingsView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import SwiftUI

struct SettingsView: View {
    private let shortcuts: [ShortcutRow] = [
        ShortcutRow(action: "Open Settings", keys: "Cmd-,"),
        ShortcutRow(action: "Refresh active pane", keys: "Cmd-R"),
        ShortcutRow(action: "Refresh both panes", keys: "Cmd-Shift-R"),
        ShortcutRow(action: "Go up", keys: "Cmd-Up"),
        ShortcutRow(action: "Show hidden files", keys: "Cmd-Shift-."),
        ShortcutRow(action: "Copy to other pane", keys: "Cmd-Option-C"),
        ShortcutRow(action: "Move to other pane", keys: "Cmd-Option-M"),
        ShortcutRow(action: "New folder", keys: "Cmd-Shift-N"),
        ShortcutRow(action: "Rename", keys: "Return"),
        ShortcutRow(action: "Preview", keys: "Space"),
        ShortcutRow(action: "Move to Trash", keys: "Cmd-Delete")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            shortcutsSection
        }
        .padding(22)
        .frame(width: 460, height: 430, alignment: .topLeading)
        .background(CatppuccinMochaTheme.appBackground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenPane Settings")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)

            Text("Quick reference for the current MVP shortcuts.")
                .font(.system(size: 12))
                .foregroundStyle(CatppuccinMochaTheme.secondaryText)
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(CatppuccinMochaTheme.mutedText)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(shortcuts) { shortcut in
                    ShortcutRowView(shortcut: shortcut)

                    if shortcut.id != shortcuts.last?.id {
                        Rectangle()
                            .fill(CatppuccinMochaTheme.surface0)
                            .frame(height: CatppuccinMochaTheme.hairlineBorderWidth)
                    }
                }
            }
            .background(
                CatppuccinMochaTheme.mantle,
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                    .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
            }
        }
    }
}

private struct ShortcutRow: Identifiable {
    let action: String
    let keys: String

    var id: String {
        action
    }
}

private struct ShortcutRowView: View {
    let shortcut: ShortcutRow

    var body: some View {
        HStack(spacing: 12) {
            Text(shortcut.action)
                .font(.system(size: 13))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)

            Spacer()

            Text(shortcut.keys)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
