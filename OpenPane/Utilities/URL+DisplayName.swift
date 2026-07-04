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

    nonisolated func isDescendant(of ancestorURL: URL) -> Bool {
        let pathComponents = standardizedFileURL.pathComponents
        let ancestorComponents = ancestorURL.standardizedFileURL.pathComponents

        guard pathComponents.count > ancestorComponents.count else {
            return false
        }

        return pathComponents.starts(with: ancestorComponents)
    }
}
