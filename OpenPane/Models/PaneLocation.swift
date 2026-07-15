//
//  PaneLocation.swift
//  OpenPane
//
//  Created by Codex on 7/11/26.
//

import Foundation

/// A location that can be displayed by a pane.
///
/// Network is intentionally a logical destination rather than a filesystem
/// URL. A mounted network share is represented by ``file(URL)`` after NetFS
/// makes its local mount point available.
nonisolated enum PaneLocation: Codable, Equatable, Hashable, Sendable {
    case file(URL)
    case network

    var fileURL: URL? {
        guard case .file(let url) = self else {
            return nil
        }

        return url
    }

    var isFileBacked: Bool {
        fileURL != nil
    }

    /// Compatibility URL for legacy URL-only APIs. Network navigation still
    /// uses the logical ``network`` case; this value is never used to browse
    /// the filesystem.
    static var networkPlaceholderURL: URL {
        URL(filePath: "/Network", directoryHint: .isDirectory)
    }

    var displayName: String {
        switch self {
        case .file(let url):
            return url.openPaneDisplayName
        case .network:
            return "Network"
        }
    }

    var pathText: String {
        switch self {
        case .file(let url):
            return url.path
        case .network:
            return "Network"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case url
    }

    private enum Kind: String, Codable {
        case file
        case network
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .file:
            self = .file(try container.decode(URL.self, forKey: .url))
        case .network:
            self = .network
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .file(let url):
            try container.encode(Kind.file, forKey: .kind)
            try container.encode(url, forKey: .url)
        case .network:
            try container.encode(Kind.network, forKey: .kind)
        }
    }
}
