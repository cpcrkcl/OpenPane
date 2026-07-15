//
//  FavoriteLocation.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/6/26.
//

import Foundation

struct FavoriteLocation: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let systemImage: String

    init(id: String? = nil, name: String, url: URL, systemImage: String) {
        self.id = id ?? url.standardizedFileURL.path
        self.name = name
        self.url = url
        self.systemImage = systemImage
    }

    init(bookmark: FavoriteBookmark, url: URL) {
        self.id = bookmark.id
        self.name = bookmark.name
        self.url = url
        self.systemImage = bookmark.systemImage
    }
}
