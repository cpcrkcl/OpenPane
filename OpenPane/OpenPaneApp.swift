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

    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        .defaultSize(width: 1240, height: 760)
    }
}
