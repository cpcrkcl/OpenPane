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
    let persistentIdentifier: String

    init(
        displayName: String,
        url: URL,
        icon: NSImage?,
        isRemovable: Bool,
        isEjectable: Bool,
        totalCapacity: Int64?,
        availableCapacity: Int64?,
        persistentIdentifier: String? = nil
    ) {
        self.displayName = displayName
        self.url = url
        self.icon = icon
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.persistentIdentifier = persistentIdentifier ?? Self.makePersistentIdentifier(for: url)
    }

    var id: URL {
        url.standardizedFileURL
    }

    static func persistentIdentifier(for url: URL, resourceValues: URLResourceValues? = nil) -> String {
        makePersistentIdentifier(for: url, resourceValues: resourceValues)
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
            lhs.availableCapacity == rhs.availableCapacity &&
            lhs.persistentIdentifier == rhs.persistentIdentifier
    }

    private static func makePersistentIdentifier(for url: URL, resourceValues: URLResourceValues? = nil) -> String {
        let standardizedURL = url.standardizedFileURL
        let resolvedResourceValues: URLResourceValues?

        if let resourceValues {
            resolvedResourceValues = resourceValues
        } else {
            resolvedResourceValues = try? standardizedURL.resourceValues(forKeys: [.volumeUUIDStringKey])
        }

        if let volumeUUIDString = resolvedResourceValues?.volumeUUIDString,
           !volumeUUIDString.isEmpty {
            return "uuid:\(volumeUUIDString.lowercased())"
        }

        return "path:\(standardizedURL.path)"
    }
}
