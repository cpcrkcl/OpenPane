//
//  KeyboardShortcutStoreTests.swift
//  OpenPaneTests
//
//  Created by OpenAI on 6/30/26.
//

import Foundation
import SwiftUI
import Testing
@testable import OpenPane

@MainActor
struct KeyboardShortcutStoreTests {
    @Test func defaultsUseReturnForOpenAndCommandReturnForRename() throws {
        let suiteName = "OpenPaneKeyboardShortcutDefaultsTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = KeyboardShortcutStore(userDefaults: userDefaults)

        #expect(store.shortcut(for: .open).key.rawValue == "return")
        #expect(!store.shortcut(for: .open).usesCommand)
        #expect(store.shortcut(for: .rename).key.rawValue == "return")
        #expect(store.shortcut(for: .rename).usesCommand)
        #expect(store.shortcut(for: .copyFiles).displayText == "⌘C")
        #expect(store.shortcut(for: .pasteFiles).displayText == "⌘V")
        #expect(store.shortcut(for: .selectAllFiles).displayText == "⌘A")
        #expect(store.shortcut(for: .duplicateFiles).displayText == "⌘D")
        #expect(store.shortcut(for: .newFile).displayText == "⌥⌘N")
    }

    @Test func savedCustomShortcutsArePreservedWhileNewDefaultsAreMerged() throws {
        let suiteName = "OpenPaneKeyboardShortcutMergeTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let customRename = OpenPaneKeyboardShortcut(
            key: ShortcutKey(rawValue: "e"),
            usesCommand: true,
            usesShift: false,
            usesOption: false,
            usesControl: false
        )
        let data = try JSONEncoder().encode([OpenPaneShortcutAction.rename.rawValue: customRename])
        userDefaults.set(data, forKey: "OpenPaneKeyboardShortcuts")

        let store = KeyboardShortcutStore(userDefaults: userDefaults)

        #expect(store.shortcut(for: .rename) == customRename)
        #expect(store.shortcut(for: .open).key.rawValue == "return")
        #expect(store.shortcut(for: .copyFiles).displayText == "⌘C")
        #expect(store.shortcut(for: .selectAllFiles).displayText == "⌘A")
        #expect(store.shortcut(for: .duplicateFiles).displayText == "⌘D")
        #expect(store.shortcut(for: .newFile).displayText == "⌥⌘N")
    }

    @Test func legacyBareReturnRenameMigratesToCommandReturn() throws {
        let suiteName = "OpenPaneKeyboardShortcutMigrationTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let legacyRename = OpenPaneKeyboardShortcut(
            key: ShortcutKey(rawValue: "return"),
            usesCommand: false,
            usesShift: false,
            usesOption: false,
            usesControl: false
        )
        let data = try JSONEncoder().encode([OpenPaneShortcutAction.rename.rawValue: legacyRename])
        userDefaults.set(data, forKey: "OpenPaneKeyboardShortcuts")

        let store = KeyboardShortcutStore(userDefaults: userDefaults)

        #expect(store.shortcut(for: .open).displayText == "Return")
        #expect(store.shortcut(for: .rename).displayText == "⌘Return")
    }

    @Test func shortcutKeyFallsBackForEmptyOrMultiCharacterRawValues() {
        #expect(ShortcutKey(rawValue: "").rawValue == "space")
        #expect(ShortcutKey(rawValue: "escape").rawValue == "space")
        #expect(ShortcutKey(rawValue: "R").rawValue == "r")
    }

    @Test func invalidSavedShortcutDataFallsBackWithoutCrashing() throws {
        let suiteName = "OpenPaneKeyboardShortcutStoreTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let savedShortcutData = try #require("""
        {
          "refreshActive": {
            "key": { "rawValue": "" },
            "usesCommand": true,
            "usesShift": false,
            "usesOption": false,
            "usesControl": false
          }
        }
        """.data(using: .utf8))
        userDefaults.set(savedShortcutData, forKey: "OpenPaneKeyboardShortcuts")

        let store = KeyboardShortcutStore(userDefaults: userDefaults)
        let shortcut = store.shortcut(for: .refreshActive)

        #expect(shortcut.key.rawValue == "space")
        _ = shortcut.keyEquivalent
    }
}
