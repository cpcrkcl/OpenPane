//
//  OpenPaneApp.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI
import AppKit

@MainActor
private final class BrowserWindowRegistry {
    static let shared = BrowserWindowRegistry()

    private let windows = NSHashTable<NSWindow>.weakObjects()
    private weak var mostRecentWindow: NSWindow?

    func register(_ window: NSWindow) {
        windows.add(window)

        if window.isKeyWindow || window.isMainWindow {
            mostRecentWindow = window
        }
    }

    func markKey(_ window: NSWindow) {
        guard windows.contains(window) else {
            return
        }

        mostRecentWindow = window
    }

    func preferredWindow(in application: NSApplication) -> NSWindow? {
        let browserWindows = application.windows.filter { window in
            windows.contains(window) && (window.isVisible || window.isMiniaturized)
        }

        if let mostRecentWindow,
           browserWindows.contains(where: { $0 === mostRecentWindow }) {
            return mostRecentWindow
        }

        return browserWindows.first
    }

    func contains(_ window: NSWindow) -> Bool {
        windows.contains(window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var commandPaletteMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        installCommandPaletteMonitor()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Ordinary activation keeps AppKit's existing window order. Recovery is
        // limited to a Dock reopen when no window is already visible.
        guard !flag else {
            return true
        }

        return !restoreBrowserWindowForReopen()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard PreviewEditSessionRegistry.shared.hasDirtySessions else {
            return .terminateNow
        }

        PreviewEditSessionRegistry.shared.resolveApplicationTermination { shouldTerminate in
            sender.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

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

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              Self.isBrowserWindow(window) else {
            return
        }

        BrowserWindowRegistry.shared.markKey(window)
    }

    private func restoreBrowserWindowForReopen() -> Bool {
        NSApp.unhide(nil)

        let activeWindows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }
        guard !activeWindows.contains(where: \.isVisible) else {
            return true
        }

        guard let window = BrowserWindowRegistry.shared.preferredWindow(in: NSApp) else {
            return false
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        return true
    }

    private static func isBrowserWindow(_ window: NSWindow) -> Bool {
        BrowserWindowRegistry.shared.contains(window)
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

private struct BrowserWindowRegistrationView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        BrowserWindowRegistrationNSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class BrowserWindowRegistrationNSView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let window {
            BrowserWindowRegistry.shared.register(window)
        }
    }
}

@main
struct OpenPaneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var keyboardShortcutStore = KeyboardShortcutStore()
    @StateObject private var volumeVisibilityStore = VolumeVisibilityStore()
    @StateObject private var favoriteStore = FavoriteStore()

    var body: some Scene {
        WindowGroup {
            MainWindowView(
                volumeVisibilityStore: volumeVisibilityStore,
                favoriteStore: favoriteStore
            )
                .environmentObject(keyboardShortcutStore)
                .background(BrowserWindowRegistrationView())
        }
        .defaultSize(width: 1240, height: 760)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Show/Hide Preview Panel") {
                    NotificationCenter.default.post(name: .togglePreviewPanel, object: nil)
                }
            }

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
            SettingsView(
                volumeVisibilityStore: volumeVisibilityStore,
                favoriteStore: favoriteStore
            )
                .environmentObject(keyboardShortcutStore)
        }
    }
}
