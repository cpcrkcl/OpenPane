//
//  FavoriteBookmark.swift
//  OpenPane
//
//  Created by Codex on 7/12/26.
//

import Foundation

struct FavoriteBookmark: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    let urlBookmarkData: Data
    let fallbackPath: String?
    var systemImage: String

    init(
        id: String = UUID().uuidString,
        name: String,
        urlBookmarkData: Data,
        fallbackPath: String? = nil,
        systemImage: String
    ) {
        self.id = id
        self.name = name
        self.urlBookmarkData = urlBookmarkData
        self.fallbackPath = fallbackPath
        self.systemImage = systemImage
    }

    init(name: String, url: URL, systemImage: String = "folder") throws {
        self.id = UUID().uuidString
        self.name = name
        self.urlBookmarkData = try Self.makeBookmarkData(for: url)
        self.fallbackPath = url.standardizedFileURL.path
        self.systemImage = systemImage
    }

    init(id: String, name: String, url: URL, systemImage: String) throws {
        self.id = id
        self.name = name
        self.urlBookmarkData = try Self.makeBookmarkData(for: url)
        self.fallbackPath = url.standardizedFileURL.path
        self.systemImage = systemImage
    }

    func resolvedURL() -> URL? {
        var isStale = false
        let resolvedURL: URL?
        if urlBookmarkData.isEmpty {
            resolvedURL = nil
        } else {
            resolvedURL = try? URL(
                resolvingBookmarkData: urlBookmarkData,
                options: Self.bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }

        let url = resolvedURL ?? fallbackPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        guard let url else { return nil }

        return url
    }

    static var usesSecurityScopedBookmarks: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        usesSecurityScopedBookmarks ? [.withSecurityScope] : []
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        usesSecurityScopedBookmarks ? [.withSecurityScope, .withoutUI] : [.withoutUI]
    }

    private static func makeBookmarkData(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            // An unsandboxed build can safely fall back to the persisted path. In a
            // sandbox, swallowing this error would create a favorite that stops
            // working after relaunch because it has no durable security scope.
            guard !usesSecurityScopedBookmarks else {
                throw error
            }
            return Data()
        }
    }
}
