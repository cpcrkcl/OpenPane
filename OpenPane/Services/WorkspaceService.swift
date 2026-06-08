//
//  WorkspaceService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/5/26.
//

import AppKit
import Foundation

nonisolated protocol WorkspaceServicing: Sendable {
    @MainActor
    func open(url: URL)

    @MainActor
    func revealInFinder(urls: [URL])

    @MainActor
    func copyPath(url: URL)

    @MainActor
    func copyText(_ text: String)
}

nonisolated struct WorkspaceService: WorkspaceServicing {
    nonisolated init() {}

    @MainActor
    func open(url: URL) {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    func revealInFinder(urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @MainActor
    func copyPath(url: URL) {
        copyText(url.path)
    }

    @MainActor
    func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
