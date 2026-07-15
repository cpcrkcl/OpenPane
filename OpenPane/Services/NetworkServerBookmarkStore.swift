//
//  NetworkServerBookmarkStore.swift
//  OpenPane
//
//  Created by Codex on 7/11/26.
//

import Foundation

nonisolated protocol NetworkServerBookmarkStoring: Sendable {
    var bookmarks: [NetworkServerBookmark] { get }

    func load() -> [NetworkServerBookmark]
    func save(_ bookmark: NetworkServerBookmark)
    func remove(_ bookmark: NetworkServerBookmark)
    func remove(id: String)
    func replace(with bookmarks: [NetworkServerBookmark])
    func removeAll()
}

/// UserDefaults-backed persistence for non-secret SMB destinations.
///
/// The model validates every URL before it reaches this store. The store also
/// decodes through that model, so malformed or credential-bearing data cannot
/// be returned to callers.
nonisolated final class NetworkServerBookmarkStore: NetworkServerBookmarkStoring, @unchecked Sendable {
    static let defaultKey = "OpenPaneNetworkServerBookmarks"

    private let userDefaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    nonisolated init(
        userDefaults: UserDefaults = .standard,
        key: String = NetworkServerBookmarkStore.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    nonisolated var bookmarks: [NetworkServerBookmark] {
        load()
    }

    nonisolated func load() -> [NetworkServerBookmark] {
        lock.withLock {
            loadLocked()
        }
    }

    nonisolated func save(_ bookmark: NetworkServerBookmark) {
        lock.withLock {
            var currentBookmarks = loadLocked()

            if let index = currentBookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                currentBookmarks[index] = bookmark
            } else {
                currentBookmarks.append(bookmark)
            }

            writeLocked(currentBookmarks)
        }
    }

    nonisolated func remove(_ bookmark: NetworkServerBookmark) {
        remove(id: bookmark.id)
    }

    nonisolated func remove(id: String) {
        lock.withLock {
            let remainingBookmarks = loadLocked().filter { $0.id != id }
            writeLocked(remainingBookmarks)
        }
    }

    nonisolated func replace(with bookmarks: [NetworkServerBookmark]) {
        lock.withLock {
            writeLocked(bookmarks)
        }
    }

    nonisolated func removeAll() {
        lock.withLock {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func loadLocked() -> [NetworkServerBookmark] {
        guard let data = userDefaults.data(forKey: key),
              let decodedBookmarks = try? decoder.decode([NetworkServerBookmark].self, from: data) else {
            return []
        }

        var uniqueBookmarks: [NetworkServerBookmark] = []
        var seenIDs = Set<String>()

        for bookmark in decodedBookmarks where seenIDs.insert(bookmark.id).inserted {
            uniqueBookmarks.append(bookmark)
        }

        return sorted(uniqueBookmarks)
    }

    private func writeLocked(_ bookmarks: [NetworkServerBookmark]) {
        let uniqueBookmarks = bookmarks.reduce(into: [NetworkServerBookmark]()) { result, bookmark in
            guard !result.contains(where: { $0.id == bookmark.id }) else {
                return
            }

            result.append(bookmark)
        }

        guard let data = try? encoder.encode(sorted(uniqueBookmarks)) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }

    private func sorted(_ bookmarks: [NetworkServerBookmark]) -> [NetworkServerBookmark] {
        bookmarks.sorted {
            let nameComparison = $0.displayName.localizedStandardCompare($1.displayName)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }
}
