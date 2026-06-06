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
}
