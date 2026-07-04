//
//  MountedVolume.swift
//  OpenPane
//
//  Created by Codex on 7/3/26.
//

import AppKit
import Foundation

struct MountedVolume: Identifiable, Equatable, @unchecked Sendable {
    let displayName: String
    let url: URL
    let icon: NSImage?
    let isRemovable: Bool
    let isEjectable: Bool
    let totalCapacity: Int64?
    let availableCapacity: Int64?

    var id: URL {
        url.standardizedFileURL
    }

    var detailText: String? {
        guard let availableCapacity else {
            return nil
        }

        let freeText = ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)

        guard let totalCapacity, totalCapacity > 0 else {
            return "\(freeText) free"
        }

        let totalText = ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
        return "\(freeText) free of \(totalText)"
    }

    static func == (lhs: MountedVolume, rhs: MountedVolume) -> Bool {
        lhs.displayName == rhs.displayName &&
            lhs.url.standardizedFileURL == rhs.url.standardizedFileURL &&
            lhs.isRemovable == rhs.isRemovable &&
            lhs.isEjectable == rhs.isEjectable &&
            lhs.totalCapacity == rhs.totalCapacity &&
            lhs.availableCapacity == rhs.availableCapacity
    }
}
