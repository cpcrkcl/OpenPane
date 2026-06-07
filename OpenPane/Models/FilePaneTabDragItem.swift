//
//  FilePaneTabDragItem.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct FilePaneTabDragItem: Codable, Sendable, Transferable {
    let tabID: FilePaneTab.ID
    let sourcePaneSide: PaneSide

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .openPaneTabDragItem)
    }
}

extension UTType {
    nonisolated static let openPaneTabDragItem = UTType(exportedAs: "cpcr.kcl.OpenPane.tab")
}
