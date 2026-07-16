//
//  FavoriteStoreTests.swift
//  OpenPaneTests
//
//  Created by Codex on 7/12/26.
//

import Foundation
import Testing
@testable import OpenPane

@MainActor
struct FavoriteStoreTests {
    @Test func seedsAndPersistsFavorites() throws {
        let userDefaults = makeUserDefaults()
        let store = FavoriteStore(userDefaults: userDefaults)

        store.seedDefaultsIfEmpty()

        #expect(store.favoriteLocations.map(\.name) == [
            "Home",
            "Desktop",
            "Documents",
            "Downloads",
            "Applications"
        ])
        #expect(store.bookmarks.allSatisfy { $0.urlBookmarkData.isEmpty })
        #expect(store.bookmarks.allSatisfy { $0.fallbackPath != nil })

        let restoredStore = FavoriteStore(userDefaults: userDefaults)
        #expect(restoredStore.favoriteLocations.map(\.name) == store.favoriteLocations.map(\.name))
    }

    @Test func addRemoveAndRenameFavorites() throws {
        let store = FavoriteStore(userDefaults: makeUserDefaults())
        let projectsURL = URL(filePath: "/tmp/OpenPaneProjects-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)

        let bookmark = try store.add(name: "Projects", url: projectsURL, systemImage: "folder")

        #expect(store.contains(url: projectsURL))
        #expect(store.favoriteLocations.map(\.name) == ["Projects"])

        store.rename(id: bookmark.id, to: "Work")
        #expect(store.favoriteLocations.first?.name == "Work")

        store.remove(id: bookmark.id)
        #expect(store.favoriteLocations.isEmpty)
        #expect(store.contains(url: projectsURL) == false)
    }

    @Test func rejectsDuplicateFavorites() throws {
        let store = FavoriteStore(userDefaults: makeUserDefaults())
        let url = URL(filePath: "/tmp/OpenPaneDuplicate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        _ = try store.add(name: "Projects", url: url)

        #expect(throws: FavoriteStoreError.alreadyExists) {
            try store.add(name: "Projects Copy", url: url)
        }
    }

    @Test func resetRestoresDefaultFavorites() throws {
        let store = FavoriteStore(userDefaults: makeUserDefaults())
        let url = URL(filePath: "/tmp/OpenPaneReset-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        _ = try store.add(name: "Custom", url: url)

        store.resetToDefaults()

        #expect(store.favoriteLocations.map(\.name) == [
            "Home",
            "Desktop",
            "Documents",
            "Downloads",
            "Applications"
        ])
    }

    @Test func reordersFavoritesAndPersistsTheNewOrder() throws {
        let userDefaults = makeUserDefaults()
        let store = FavoriteStore(userDefaults: userDefaults)
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneFavoriteOrder-\(UUID().uuidString)", isDirectory: true)
        let firstURL = rootURL.appendingPathComponent("First", isDirectory: true)
        let secondURL = rootURL.appendingPathComponent("Second", isDirectory: true)
        let thirdURL = rootURL.appendingPathComponent("Third", isDirectory: true)
        try FileManager.default.createDirectory(at: firstURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thirdURL, withIntermediateDirectories: true)

        _ = try store.add(name: "First", url: firstURL)
        _ = try store.add(name: "Second", url: secondURL)
        _ = try store.add(name: "Third", url: thirdURL)
        store.reorder(from: IndexSet(integer: 0), to: 3)

        #expect(store.favoriteLocations.map(\.name) == ["Second", "Third", "First"])
        #expect(
            FavoriteStore(userDefaults: userDefaults).favoriteLocations.map(\.name) ==
                ["Second", "Third", "First"]
        )
    }

    @Test func deliberatelyEmptyListStaysEmptyAcrossLaunches() {
        let userDefaults = makeUserDefaults()
        let store = FavoriteStore(userDefaults: userDefaults)
        store.seedDefaultsIfNeeded()

        for bookmark in store.bookmarks {
            store.remove(id: bookmark.id)
        }

        let restoredStore = FavoriteStore(userDefaults: userDefaults)
        restoredStore.seedDefaultsIfNeeded()

        #expect(restoredStore.bookmarks.isEmpty)
        #expect(restoredStore.favoriteLocations.isEmpty)
    }

    @Test func corruptPersistenceRecoversAsAnUninitializedStore() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(Data("not-json".utf8), forKey: FavoriteStore.defaultUserDefaultsKey)

        let store = FavoriteStore(userDefaults: userDefaults)

        #expect(store.bookmarks.isEmpty)
        #expect(userDefaults.object(forKey: FavoriteStore.defaultUserDefaultsKey) == nil)

        store.seedDefaultsIfNeeded()
        #expect(store.bookmarks.count == 5)
    }

    @Test func loadSanitizesDuplicateAndMalformedBookmarks() throws {
        let userDefaults = makeUserDefaults()
        let firstPath = "/tmp/OpenPaneSanitizedFirst"
        let secondPath = "/tmp/OpenPaneSanitizedSecond"
        let candidates = [
            FavoriteBookmark(
                id: "duplicate-id",
                name: "  First  ",
                urlBookmarkData: Data(),
                fallbackPath: "\(firstPath)/../OpenPaneSanitizedFirst",
                systemImage: ""
            ),
            FavoriteBookmark(
                id: "duplicate-id",
                name: "Second",
                urlBookmarkData: Data(),
                fallbackPath: secondPath,
                systemImage: "folder"
            ),
            FavoriteBookmark(
                id: "duplicate-path",
                name: "Duplicate Path",
                urlBookmarkData: Data(),
                fallbackPath: secondPath,
                systemImage: "folder"
            ),
            FavoriteBookmark(
                id: "invalid",
                name: "   ",
                urlBookmarkData: Data(),
                fallbackPath: nil,
                systemImage: "folder"
            )
        ]
        userDefaults.set(
            try JSONEncoder().encode(candidates),
            forKey: FavoriteStore.defaultUserDefaultsKey
        )

        let store = FavoriteStore(userDefaults: userDefaults)

        #expect(store.bookmarks.count == 2)
        #expect(store.bookmarks.map(\.name) == ["First", "Second"])
        #expect(Set(store.bookmarks.map(\.id)).count == 2)
        #expect(store.bookmarks.first?.systemImage == "folder")
        #expect(store.favoriteLocations.map(\.url.path) == [firstPath, secondPath])
    }

    @Test func addRejectsMissingPathsAndFiles() throws {
        let store = FavoriteStore(userDefaults: makeUserDefaults())
        let missingURL = URL(
            filePath: "/tmp/OpenPaneMissingFavorite-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneFavoriteFile-\(UUID().uuidString)")
        try Data("file".utf8).write(to: fileURL)

        #expect(throws: FavoriteStoreError.invalidFolder) {
            try store.add(name: "Missing", url: missingURL)
        }
        #expect(throws: FavoriteStoreError.invalidFolder) {
            try store.add(name: "File", url: fileURL)
        }
    }

    @Test func addNormalizesBlankMetadata() throws {
        let store = FavoriteStore(userDefaults: makeUserDefaults())
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneFavoriteMetadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let bookmark = try store.add(name: "  ", url: directoryURL, systemImage: "  ")

        #expect(bookmark.name == directoryURL.lastPathComponent)
        #expect(bookmark.systemImage == "folder")
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "OpenPaneFavoriteStoreTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}
