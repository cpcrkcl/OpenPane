//
//  SessionState.swift
//  OpenPane
//
//  Created by Codex on 7/3/26.
//

import Foundation

struct SessionState: Codable, Equatable, Sendable {
    var leftPane: SessionPaneState
    var rightPane: SessionPaneState
    var activePaneSide: PaneSide
    var splitLeftPaneFraction: Double?
}

struct SessionPaneState: Codable, Equatable, Sendable {
    var tabs: [SessionTabState]
    var activeTabID: UUID
    var currentURL: URL
    var includeHiddenFiles: Bool
    var sortOption: FileSortOption
    var sortDirection: FileSortDirection
    var directoriesFirst: Bool
}

struct SessionTabState: Codable, Equatable, Sendable {
    var id: UUID
    var currentURL: URL
}
