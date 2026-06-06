//
//  FavoriteLocation.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/6/26.
//

import Foundation

struct FavoriteLocation: Identifiable, Hashable, Sendable {
    let id: URL
    let name: String
    let url: URL
    let systemImage: String

    init(name: String, url: URL, systemImage: String) {
        self.id = url
        self.name = name
        self.url = url
        self.systemImage = systemImage
    }
}
