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
