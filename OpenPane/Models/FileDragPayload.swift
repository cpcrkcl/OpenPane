//
//  FileDragPayload.swift
//  OpenPane
//
//  Created by Codex on 6/8/26.
//

import Foundation
import UniformTypeIdentifiers

nonisolated struct FileDragPayload: Codable, Sendable {
    let sourcePaneSide: PaneSide?
    let fileURLs: [URL]

    init(sourcePaneSide: PaneSide?, fileURLs: [URL]) {
        self.sourcePaneSide = sourcePaneSide
        self.fileURLs = fileURLs
    }

    static var typeIdentifier: String {
        UTType.openPaneFileDragPayload.identifier
    }

    var encodedData: Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) -> FileDragPayload? {
        try? JSONDecoder().decode(Self.self, from: data)
    }
}

extension UTType {
    nonisolated static let openPaneFileDragPayload = UTType(exportedAs: "cpcr.kcl.OpenPane.file-drag-payload")
}
