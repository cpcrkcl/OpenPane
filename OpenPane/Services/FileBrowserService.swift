//
//  FileBrowserService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation

nonisolated struct FileBrowserService: Sendable {
    nonisolated func contentsOfDirectory(at url: URL, includeHiddenFiles: Bool) async throws -> [FileItem] {
        try await Task.detached(priority: .userInitiated) {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(FileItem.resourceKeys),
                options: []
            )

            return try fileURLs
                .map(FileItem.init)
                .filter { item in
                    includeHiddenFiles || (!item.isHidden && !item.name.hasPrefix("."))
                }
                .sorted(by: Self.sortItems)
        }.value
    }

    private nonisolated static func sortItems(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
