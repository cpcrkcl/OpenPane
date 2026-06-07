//
//  FilePaneTab.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import Foundation

struct FilePaneTab: Identifiable, Equatable, Sendable {
    let id: UUID
    var currentURL: URL
    var items: [FileItem]
    var selectedItems: Set<FileItem>

    init(
        id: UUID = UUID(),
        currentURL: URL,
        items: [FileItem] = [],
        selectedItems: Set<FileItem> = []
    ) {
        self.id = id
        self.currentURL = currentURL
        self.items = items
        self.selectedItems = selectedItems
    }

    var title: String {
        currentURL.openPaneDisplayName
    }
}
