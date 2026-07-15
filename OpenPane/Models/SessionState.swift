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
    var location: PaneLocation
    var includeHiddenFiles: Bool
    var sortOption: FileSortOption
    var sortDirection: FileSortDirection

    var currentURL: URL {
        get {
            location.fileURL ?? PaneLocation.networkPlaceholderURL
        }
        set {
            location = .file(newValue)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case tabs
        case activeTabID
        case location
        case currentURL
        case includeHiddenFiles
        case sortOption
        case sortDirection
    }

    init(
        tabs: [SessionTabState],
        activeTabID: UUID,
        location: PaneLocation,
        includeHiddenFiles: Bool,
        sortOption: FileSortOption,
        sortDirection: FileSortDirection
    ) {
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.location = location
        self.includeHiddenFiles = includeHiddenFiles
        self.sortOption = sortOption
        self.sortDirection = sortDirection
    }

    init(
        tabs: [SessionTabState],
        activeTabID: UUID,
        currentURL: URL,
        includeHiddenFiles: Bool,
        sortOption: FileSortOption,
        sortDirection: FileSortDirection
    ) {
        self.init(
            tabs: tabs,
            activeTabID: activeTabID,
            location: .file(currentURL),
            includeHiddenFiles: includeHiddenFiles,
            sortOption: sortOption,
            sortDirection: sortDirection
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try container.decode([SessionTabState].self, forKey: .tabs)
        activeTabID = try container.decode(UUID.self, forKey: .activeTabID)
        if let location = try container.decodeIfPresent(PaneLocation.self, forKey: .location) {
            self.location = location
        } else {
            self.location = .file(try container.decode(URL.self, forKey: .currentURL))
        }
        includeHiddenFiles = try container.decode(Bool.self, forKey: .includeHiddenFiles)
        sortOption = try container.decode(FileSortOption.self, forKey: .sortOption)
        sortDirection = try container.decode(FileSortDirection.self, forKey: .sortDirection)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tabs, forKey: .tabs)
        try container.encode(activeTabID, forKey: .activeTabID)
        try container.encode(location, forKey: .location)
        try container.encode(includeHiddenFiles, forKey: .includeHiddenFiles)
        try container.encode(sortOption, forKey: .sortOption)
        try container.encode(sortDirection, forKey: .sortDirection)
    }
}

struct SessionTabState: Codable, Equatable, Sendable {
    var id: UUID
    var location: PaneLocation

    var currentURL: URL {
        get {
            location.fileURL ?? PaneLocation.networkPlaceholderURL
        }
        set {
            location = .file(newValue)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case location
        case currentURL
    }

    init(id: UUID, location: PaneLocation) {
        self.id = id
        self.location = location
    }

    init(id: UUID, currentURL: URL) {
        self.init(id: id, location: .file(currentURL))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        if let location = try container.decodeIfPresent(PaneLocation.self, forKey: .location) {
            self.location = location
        } else {
            self.location = .file(try container.decode(URL.self, forKey: .currentURL))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(location, forKey: .location)
    }
}
