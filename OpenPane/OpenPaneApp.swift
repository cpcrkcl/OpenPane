//
//  OpenPaneApp.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

@main
struct OpenPaneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var keyboardShortcutStore = KeyboardShortcutStore()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(keyboardShortcutStore)
        }
        .defaultSize(width: 1240, height: 760)

        Settings {
            SettingsView()
                .environmentObject(keyboardShortcutStore)
        }
    }
}
