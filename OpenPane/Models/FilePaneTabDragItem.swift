//
//  FilePaneTabDragItem.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import Foundation
import UniformTypeIdentifiers

nonisolated struct FilePaneTabDragItem: Codable, Sendable {
    let tabID: FilePaneTab.ID
    let sourcePaneSide: PaneSide
    let location: PaneLocation?

    var currentURL: URL? {
        location?.fileURL
    }

    init(tabID: FilePaneTab.ID, sourcePaneSide: PaneSide, location: PaneLocation? = nil) {
        self.tabID = tabID
        self.sourcePaneSide = sourcePaneSide
        self.location = location
    }

    init(tabID: FilePaneTab.ID, sourcePaneSide: PaneSide, currentURL: URL? = nil) {
        self.init(
            tabID: tabID,
            sourcePaneSide: sourcePaneSide,
            location: currentURL.map(PaneLocation.file)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case tabID
        case sourcePaneSide
        case location
        case currentURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabID = try container.decode(FilePaneTab.ID.self, forKey: .tabID)
        sourcePaneSide = try container.decode(PaneSide.self, forKey: .sourcePaneSide)
        location = try container.decodeIfPresent(PaneLocation.self, forKey: .location)
            ?? container.decodeIfPresent(URL.self, forKey: .currentURL).map(PaneLocation.file)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tabID, forKey: .tabID)
        try container.encode(sourcePaneSide, forKey: .sourcePaneSide)
        try container.encodeIfPresent(location, forKey: .location)
    }

    static var typeIdentifier: String {
        UTType.openPaneTabDragItem.identifier
    }

    var encodedData: Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) -> FilePaneTabDragItem? {
        try? JSONDecoder().decode(Self.self, from: data)
    }
}

extension UTType {
    nonisolated static let openPaneTabDragItem = UTType(exportedAs: "cpcr.kcl.OpenPane.tab")
}
