//
//  OpenPaneApp.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var commandPaletteMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        installCommandPaletteMonitor()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        bringApplicationWindowForwardIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringApplicationWindowForwardIfNeeded()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let commandPaletteMonitor {
            NSEvent.removeMonitor(commandPaletteMonitor)
        }
    }

    private func installCommandPaletteMonitor() {
        commandPaletteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Self.isCommandPaletteShortcut(event) else {
                return event
            }

            Self.openCommandPalette()
            return nil
        }
    }

    private static func openCommandPalette() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .openCommandPalette, object: nil)
        }
    }

    private func bringApplicationWindowForwardIfNeeded() {
        NSApp.unhide(nil)

        guard let window = NSApp.windows.first(where: { window in
            window.canBecomeKey &&
                window.level == .normal
        }) else {
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func isCommandPaletteShortcut(_ event: NSEvent) -> Bool {
        let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let disallowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift]

        return NSApp.isActive &&
            relevantModifiers.contains(.command) &&
            relevantModifiers.intersection(disallowedModifiers).isEmpty &&
            (event.charactersIgnoringModifiers?.lowercased() == "k" || event.keyCode == 40)
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
        .commands {
            CommandMenu("Tools") {
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Switch Active Pane") {
                    NotificationCenter.default.post(name: .switchActivePane, object: nil)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(keyboardShortcutStore)
        }
    }
}
