//
//  FavoriteStore.swift
//  OpenPane
//
//  Created by Codex on 7/12/26.
//

import Combine
import Foundation

@MainActor
final class FavoriteStore: ObservableObject {
    nonisolated static let defaultUserDefaultsKey = "OpenPaneFavoriteBookmarks"

    @Published private(set) var bookmarks: [FavoriteBookmark]

    private let userDefaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var resolvedURLsByID: [String: URL] = [:]
    private var accessedSecurityScopedBookmarkIDs: Set<String> = []

    init(
        userDefaults: UserDefaults = .standard,
        key: String = FavoriteStore.defaultUserDefaultsKey
    ) {
        self.userDefaults = userDefaults
        self.key = key

        if let data = userDefaults.data(forKey: key),
           let decoded = try? decoder.decode([FavoriteBookmark].self, from: data) {
            let sanitized = Self.sanitized(decoded)
            self.bookmarks = sanitized
            if sanitized != decoded, let sanitizedData = try? encoder.encode(sanitized) {
                userDefaults.set(sanitizedData, forKey: key)
            }
        } else {
            self.bookmarks = []
            // Treat an unreadable value as uninitialized so the application can
            // recover by seeding defaults instead of remaining permanently empty.
            if userDefaults.object(forKey: key) != nil {
                userDefaults.removeObject(forKey: key)
            }
        }
    }

    var favoriteLocations: [FavoriteLocation] {
        bookmarks.compactMap { bookmark in
            guard let url = resolvedURL(for: bookmark) else {
                return nil
            }

            return FavoriteLocation(bookmark: bookmark, url: url)
        }
    }

    func contains(url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        return favoriteLocations.contains { $0.url.standardizedFileURL == standardized }
    }

    @discardableResult
    func add(name: String, url: URL, systemImage: String = "folder") throws -> FavoriteBookmark {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard standardized.isFileURL,
              FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FavoriteStoreError.invalidFolder
        }
        guard !contains(url: standardized) else {
            throw FavoriteStoreError.alreadyExists
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = try FavoriteBookmark(
            name: trimmedName.isEmpty ? standardized.openPaneDisplayName : trimmedName,
            url: standardized,
            systemImage: systemImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "folder"
                : systemImage
        )
        bookmarks.append(bookmark)
        persist()
        return bookmark
    }

    func remove(id: String) {
        let originalCount = bookmarks.count
        bookmarks.removeAll { $0.id == id }
        guard bookmarks.count != originalCount else {
            return
        }

        stopAccessingSecurityScopedResource(for: id)
        persist()
    }

    func rename(id: String, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = bookmarks.firstIndex(where: { $0.id == id }),
              bookmarks[index].name != trimmedName else {
            return
        }

        bookmarks[index].name = trimmedName
        persist()
    }

    func reorder(from source: IndexSet, to destination: Int) {
        let validSource = source.filter { bookmarks.indices.contains($0) }
        guard !validSource.isEmpty else {
            return
        }

        let movedBookmarks = validSource.map { bookmarks[$0] }

        let adjustedDestination = min(
            max(0, destination - validSource.filter { $0 < destination }.count),
            bookmarks.count - movedBookmarks.count
        )
        for index in validSource.sorted(by: >) {
            bookmarks.remove(at: index)
        }
        bookmarks.insert(contentsOf: movedBookmarks, at: adjustedDestination)
        persist()
    }

    func replace(with bookmarks: [FavoriteBookmark]) {
        stopAccessingAllSecurityScopedResources()
        self.bookmarks = Self.sanitized(bookmarks)
        persist()
    }

    func resetToDefaults(fileManager: FileManager = .default) {
        stopAccessingAllSecurityScopedResources()
        bookmarks = Self.defaultBookmarks(fileManager: fileManager)
        persist()
    }

    func seedDefaultsIfEmpty(fileManager: FileManager = .default) {
        guard bookmarks.isEmpty else {
            return
        }

        stopAccessingAllSecurityScopedResources()
        bookmarks = Self.defaultBookmarks(fileManager: fileManager)
        persist()
    }

    /// Seeds a new store, but preserves a deliberately empty persisted list.
    func seedDefaultsIfNeeded(fileManager: FileManager = .default) {
        guard userDefaults.object(forKey: key) == nil else {
            return
        }

        bookmarks = Self.defaultBookmarks(fileManager: fileManager)
        persist()
    }

    private func resolvedURL(for bookmark: FavoriteBookmark) -> URL? {
        if let cachedURL = resolvedURLsByID[bookmark.id] {
            return cachedURL
        }

        guard let url = bookmark.resolvedURL() else {
            return nil
        }

        resolvedURLsByID[bookmark.id] = url
        if FavoriteBookmark.usesSecurityScopedBookmarks,
           url.startAccessingSecurityScopedResource() {
            accessedSecurityScopedBookmarkIDs.insert(bookmark.id)
        }
        return url
    }

    private func stopAccessingSecurityScopedResource(for id: String) {
        if accessedSecurityScopedBookmarkIDs.remove(id) != nil {
            resolvedURLsByID[id]?.stopAccessingSecurityScopedResource()
        }
        resolvedURLsByID[id] = nil
    }

    private func stopAccessingAllSecurityScopedResources() {
        for id in accessedSecurityScopedBookmarkIDs {
            resolvedURLsByID[id]?.stopAccessingSecurityScopedResource()
        }
        accessedSecurityScopedBookmarkIDs.removeAll()
        resolvedURLsByID.removeAll()
    }

    private func persist() {
        guard let data = try? encoder.encode(bookmarks) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }

    private static func sanitized(_ candidates: [FavoriteBookmark]) -> [FavoriteBookmark] {
        var result: [FavoriteBookmark] = []
        var seenIDs: Set<String> = []
        var seenPaths: Set<String> = []
        var seenBookmarkData: Set<Data> = []

        for candidate in candidates {
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                continue
            }

            let fallbackPath: String?
            if let rawPath = candidate.fallbackPath,
               rawPath.hasPrefix("/") {
                fallbackPath = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL.path
            } else {
                fallbackPath = nil
            }

            guard !candidate.urlBookmarkData.isEmpty || fallbackPath != nil else {
                continue
            }

            if let fallbackPath {
                guard seenPaths.insert(fallbackPath).inserted else {
                    continue
                }
            } else {
                guard seenBookmarkData.insert(candidate.urlBookmarkData).inserted else {
                    continue
                }
            }

            var id = candidate.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty || !seenIDs.insert(id).inserted {
                repeat {
                    id = UUID().uuidString
                } while !seenIDs.insert(id).inserted
            }

            let icon = candidate.systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(
                FavoriteBookmark(
                    id: id,
                    name: name,
                    urlBookmarkData: candidate.urlBookmarkData,
                    fallbackPath: fallbackPath,
                    systemImage: icon.isEmpty ? "folder" : icon
                )
            )
        }

        return result
    }

    private static func defaultBookmarks(fileManager: FileManager) -> [FavoriteBookmark] {
        defaultFavoriteLocations(fileManager: fileManager).compactMap { location in
            try? FavoriteBookmark(
                id: "builtin:\(location.url.standardizedFileURL.path)",
                name: location.name,
                url: location.url,
                systemImage: location.systemImage
            )
        }
    }

    private static func defaultFavoriteLocations(fileManager: FileManager) -> [FavoriteLocation] {
        let homeURL = fileManager.homeDirectoryForCurrentUser

        return [
            FavoriteLocation(
                id: "builtin:home",
                name: "Home",
                url: homeURL,
                systemImage: "house"
            ),
            FavoriteLocation(
                id: "builtin:desktop",
                name: "Desktop",
                url: standardDirectoryURL(.desktopDirectory, fileManager: fileManager)
                    ?? homeURL.appendingPathComponent("Desktop", isDirectory: true),
                systemImage: "display"
            ),
            FavoriteLocation(
                id: "builtin:documents",
                name: "Documents",
                url: standardDirectoryURL(.documentDirectory, fileManager: fileManager)
                    ?? homeURL.appendingPathComponent("Documents", isDirectory: true),
                systemImage: "doc.text"
            ),
            FavoriteLocation(
                id: "builtin:downloads",
                name: "Downloads",
                url: standardDirectoryURL(.downloadsDirectory, fileManager: fileManager)
                    ?? homeURL.appendingPathComponent("Downloads", isDirectory: true),
                systemImage: "arrow.down.circle"
            ),
            FavoriteLocation(
                id: "builtin:applications",
                name: "Applications",
                url: applicationsURL(fileManager: fileManager),
                systemImage: "square.grid.2x2"
            )
        ]
    }

    private static func standardDirectoryURL(
        _ directory: FileManager.SearchPathDirectory,
        fileManager: FileManager
    ) -> URL? {
        fileManager.urls(for: directory, in: .userDomainMask).first
    }

    private static func applicationsURL(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first
            ?? fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first
            ?? URL(filePath: "/Applications", directoryHint: .isDirectory)
    }
}

enum FavoriteStoreError: LocalizedError {
    case alreadyExists
    case invalidFolder
    case unavailableOnNetworkPage

    var errorDescription: String? {
        switch self {
        case .alreadyExists:
            return "This folder is already in Favorites."
        case .invalidFolder:
            return "Only an existing folder can be added to Favorites."
        case .unavailableOnNetworkPage:
            return "Favorites are unavailable on the Network page."
        }
    }
}
