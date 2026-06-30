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
