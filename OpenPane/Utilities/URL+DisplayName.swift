//
//  URL+DisplayName.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import Foundation

extension URL {
    nonisolated var openPaneDisplayName: String {
        lastPathComponent.isEmpty ? path : lastPathComponent
    }
}
