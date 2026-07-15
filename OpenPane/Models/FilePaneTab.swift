//
//  FilePaneTab.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import Foundation

struct FilePaneTab: Identifiable, Equatable, Sendable {
    let id: UUID
    var location: PaneLocation
    var items: [FileItem]
    var selectedItems: Set<FileItem>
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        location: PaneLocation,
        items: [FileItem] = [],
        selectedItems: Set<FileItem> = [],
        isDirty: Bool = false
    ) {
        self.id = id
        self.location = location
        self.items = items
        self.selectedItems = selectedItems
        self.isDirty = isDirty
    }

    var currentURL: URL {
        get {
            location.fileURL ?? PaneLocation.networkPlaceholderURL
        }
        set {
            location = .file(newValue)
        }
    }

    init(
        id: UUID = UUID(),
        currentURL: URL,
        items: [FileItem] = [],
        selectedItems: Set<FileItem> = [],
        isDirty: Bool = false
    ) {
        self.init(
            id: id,
            location: .file(currentURL),
            items: items,
            selectedItems: selectedItems,
            isDirty: isDirty
        )
    }

    var title: String {
        location.displayName
    }
}
