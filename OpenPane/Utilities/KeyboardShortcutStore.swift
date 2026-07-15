//
//  KeyboardShortcutStore.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import AppKit
import Combine
import SwiftUI

enum OpenPaneShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case goBack
    case goForward
    case refreshActive
    case refreshBoth
    case goUp
    case toggleHiddenFiles
    case copyToOtherPane
    case moveToOtherPane
    case newFolder
    case open
    case rename
    case preview
    case copyFiles
    case pasteFiles
    case selectAllFiles
    case duplicateFiles
    case newFile
    case moveToTrash
    case searchSubtree
    case goToFolder

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .goBack:
            "Back"
        case .goForward:
            "Forward"
        case .refreshActive:
            "Refresh active pane"
        case .refreshBoth:
            "Refresh both panes"
        case .goUp:
            "Go up"
        case .toggleHiddenFiles:
            "Show hidden files"
        case .copyToOtherPane:
            "Copy to other pane"
        case .moveToOtherPane:
            "Move to other pane"
        case .newFolder:
            "New folder"
        case .open:
            "Open focused item"
        case .rename:
            "Rename"
        case .preview:
            "Preview"
        case .copyFiles:
            "Copy selected files"
        case .pasteFiles:
            "Paste files"
        case .selectAllFiles:
            "Select all files"
        case .duplicateFiles:
            "Duplicate selected files"
        case .newFile:
            "New file"
        case .moveToTrash:
            "Move to Trash"
        case .searchSubtree:
            "Search subtree"
        case .goToFolder:
            "Go to folder"
        }
    }
}

struct OpenPaneKeyboardShortcut: Codable, Equatable, Sendable {
    var key: ShortcutKey
    var usesCommand: Bool
    var usesShift: Bool
    var usesOption: Bool
    var usesControl: Bool

    var keyEquivalent: KeyEquivalent {
        key.keyEquivalent
    }

    var modifiers: EventModifiers {
        var modifiers = EventModifiers()

        if usesCommand {
            modifiers.insert(.command)
        }

        if usesShift {
            modifiers.insert(.shift)
        }

        if usesOption {
            modifiers.insert(.option)
        }

        if usesControl {
            modifiers.insert(.control)
        }

        return modifiers
    }

    var displayText: String {
        "\(modifierDisplayText)\(key.displayText)"
    }

    private var modifierDisplayText: String {
        var text = ""

        if usesControl {
            text += "⌃"
        }

        if usesOption {
            text += "⌥"
        }

        if usesShift {
            text += "⇧"
        }

        if usesCommand {
            text += "⌘"
        }

        return text
    }
}

struct ShortcutKey: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case rawValue
    }

    private static let fallbackRawValue = "space"
    private static let specialRawValues: Set<String> = [
        "return",
        "delete",
        "upArrow",
        "space"
    ]

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = Self.validatedRawValue(rawValue) ?? Self.fallbackRawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedRawValue = try container.decodeIfPresent(String.self, forKey: .rawValue) ?? Self.fallbackRawValue
        self.init(rawValue: decodedRawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }

    var keyEquivalent: KeyEquivalent {
        switch rawValue {
        case "return":
            .return
        case "delete":
            .delete
        case "upArrow":
            .upArrow
        case "space":
            .space
        default:
            if let character = Self.singleCharacter(from: rawValue) {
                KeyEquivalent(character)
            } else {
                .space
            }
        }
    }

    var displayText: String {
        switch rawValue {
        case "return":
            "Return"
        case "delete":
            "Delete"
        case "upArrow":
            "↑"
        case "space":
            "Space"
        default:
            rawValue.uppercased()
        }
    }

    private static func validatedRawValue(_ rawValue: String) -> String? {
        let trimmedRawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedRawValue.isEmpty else {
            return nil
        }

        if specialRawValues.contains(trimmedRawValue) {
            return trimmedRawValue
        }

        let lowercasedRawValue = trimmedRawValue.lowercased()
        guard singleCharacter(from: lowercasedRawValue) != nil else {
            return nil
        }

        return lowercasedRawValue
    }

    private static func singleCharacter(from rawValue: String) -> Character? {
        let characters = Array(rawValue)
        guard characters.count == 1 else {
            return nil
        }

        return characters[0]
    }
}

@MainActor
final class KeyboardShortcutStore: ObservableObject {
    @Published private var shortcuts: [OpenPaneShortcutAction: OpenPaneKeyboardShortcut]

    private let userDefaults: UserDefaults
    private let userDefaultsKey = "OpenPaneKeyboardShortcuts"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let data = userDefaults.data(forKey: userDefaultsKey),
           let savedShortcuts = try? JSONDecoder().decode([String: OpenPaneKeyboardShortcut].self, from: data) {
            var resolvedSavedShortcuts = savedShortcuts.compactMapKeys(OpenPaneShortcutAction.init(rawValue:))
            let shouldMigrateLegacyReturnRename = resolvedSavedShortcuts[.open] == nil &&
                resolvedSavedShortcuts[.rename] == Self.legacyRenameShortcut
            if shouldMigrateLegacyReturnRename {
                resolvedSavedShortcuts[.rename] = Self.defaultShortcuts[.rename]
            }

            shortcuts = Self.defaultShortcuts.merging(resolvedSavedShortcuts) { _, saved in
                saved
            }
            if shouldMigrateLegacyReturnRename {
                save()
            }
        } else {
            shortcuts = Self.defaultShortcuts
        }
    }

    func shortcut(for action: OpenPaneShortcutAction) -> OpenPaneKeyboardShortcut {
        shortcuts[action] ?? Self.defaultShortcuts[action] ?? Self.fallbackShortcut
    }

    func setShortcut(_ shortcut: OpenPaneKeyboardShortcut, for action: OpenPaneShortcutAction) {
        shortcuts[action] = shortcut
        save()
    }

    func resetToDefaults() {
        shortcuts = Self.defaultShortcuts
        save()
    }

    private func save() {
        let encodedShortcuts = shortcuts.reduce(into: [String: OpenPaneKeyboardShortcut]()) { result, pair in
            result[pair.key.rawValue] = pair.value
        }

        if let data = try? JSONEncoder().encode(encodedShortcuts) {
            userDefaults.set(data, forKey: userDefaultsKey)
        }
    }

    private static let fallbackShortcut = OpenPaneKeyboardShortcut(
        key: ShortcutKey(rawValue: "space"),
        usesCommand: false,
        usesShift: false,
        usesOption: false,
        usesControl: false
    )

    private static let legacyRenameShortcut = OpenPaneKeyboardShortcut(
        key: ShortcutKey(rawValue: "return"),
        usesCommand: false,
        usesShift: false,
        usesOption: false,
        usesControl: false
    )

    private static let defaultShortcuts: [OpenPaneShortcutAction: OpenPaneKeyboardShortcut] = [
        .goBack: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "["), usesCommand: true, usesShift: false, usesOption: false, usesControl: false),
        .goForward: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "]"), usesCommand: true, usesShift: false, usesOption: false, usesControl: false),
        .refreshActive: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "r"), usesCommand: true, usesShift: false, usesOption: false, usesControl: false),
        .refreshBoth: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "r"), usesCommand: true, usesShift: true, usesOption: false, usesControl: false),
        .goUp: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "upArrow"), usesCommand: true, usesShift: false, usesOption: false, usesControl: false),
        .toggleHiddenFiles: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "."), usesCommand: true, usesShift: true, usesOption: false, usesControl: false),
        .copyToOtherPane: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "c"), usesCommand: true, usesShift: false, usesOption: true, usesControl: false),
        .moveToOtherPane: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "m"), usesCommand: true, usesShift: false, usesOption: true, usesControl: false),
        .newFolder: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "n"), usesCommand: true, usesShift: true, usesOption: false, usesControl: false),
        .open: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "return"), usesCommand: false, usesShift: false, usesOption: false, usesControl: false),
        .rename: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "return"), usesCommand: true, usesShift: false, usesOption: false, usesControl: false),
        .preview: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "space"), usesCommand: false, usesShift: false, usesOption: false, usesControl: false),
        .copyFiles: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "c"), usesCommand: true, usesShift: false, usesOption: false, usesControl: false),
        .pasteFiles: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "v"), usesCommand: true, usesShift: false, usesOption: false, usesControl: false),
        .selectAllFiles: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "a"), usesCommand: true, usesShift: false, usesOption: false, usesControl: false),
        .duplicateFiles: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "d"), usesCommand: true, usesShift: false, usesOption: false, usesControl: false),
        .newFile: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "n"), usesCommand: true, usesShift: false, usesOption: true, usesControl: false),
        .moveToTrash: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "delete"), usesCommand: true, usesShift: false, usesOption: false, usesControl: false),
        .searchSubtree: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "f"), usesCommand: true, usesShift: true, usesOption: false, usesControl: false),
        .goToFolder: OpenPaneKeyboardShortcut(key: ShortcutKey(rawValue: "g"), usesCommand: true, usesShift: true, usesOption: false, usesControl: false)
    ]
}

extension OpenPaneKeyboardShortcut {
    func matches(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let expectedFlags: NSEvent.ModifierFlags = [
            usesCommand ? .command : [],
            usesShift ? .shift : [],
            usesOption ? .option : [],
            usesControl ? .control : []
        ].reduce(into: []) { $0.formUnion($1) }

        return flags.intersection([.command, .shift, .option, .control]) == expectedFlags &&
            key.matches(event)
    }
}

private extension ShortcutKey {
    func matches(_ event: NSEvent) -> Bool {
        switch rawValue {
        case "return":
            return event.keyCode == 36 || event.keyCode == 76
        case "delete":
            return event.keyCode == 51 || event.keyCode == 117
        case "upArrow":
            return event.keyCode == 126
        case "space":
            return event.keyCode == 49
        default:
            return event.charactersIgnoringModifiers?.lowercased() == rawValue
        }
    }
}

private extension Dictionary {
    func compactMapKeys<NewKey: Hashable>(_ transform: (Key) -> NewKey?) -> [NewKey: Value] {
        reduce(into: [NewKey: Value]()) { result, pair in
            guard let key = transform(pair.key) else {
                return
            }

            result[key] = pair.value
        }
    }
}

extension View {
    func openPaneKeyboardShortcut(_ shortcut: OpenPaneKeyboardShortcut) -> some View {
        keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.modifiers)
    }
}
