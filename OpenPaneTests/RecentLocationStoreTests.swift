//
//  RecentLocationStoreTests.swift
//  OpenPaneTests
//

import Foundation
import Testing
@testable import OpenPane

@MainActor
struct RecentLocationStoreTests {
    @Test func recordsUniquePathsInMostRecentOrderAndPersistsThem() {
        let userDefaults = makeUserDefaults()
        let store = RecentLocationStore(userDefaults: userDefaults, maximumCount: 2)
        let firstURL = URL(filePath: "/tmp/OpenPaneRecentFirst", directoryHint: .isDirectory)
        let secondURL = URL(filePath: "/tmp/OpenPaneRecentSecond", directoryHint: .isDirectory)
        let thirdURL = URL(filePath: "/tmp/OpenPaneRecentThird", directoryHint: .isDirectory)

        store.record(firstURL)
        store.record(secondURL)
        store.record(firstURL)
        store.record(thirdURL)

        #expect(store.recentPaths == [thirdURL.path, firstURL.path])
        #expect(
            RecentLocationStore(userDefaults: userDefaults, maximumCount: 2).recentPaths ==
                [thirdURL.path, firstURL.path]
        )
    }

    @Test func sanitizesPersistedPathsAndEnforcesMaximumOnLoad() {
        let userDefaults = makeUserDefaults()
        let key = "Recent"
        userDefaults.set(
            [
                "/tmp/First/../First",
                "relative/path",
                "/tmp/Second",
                "/tmp/Second",
                "/tmp/Third"
            ],
            forKey: key
        )

        let store = RecentLocationStore(userDefaults: userDefaults, key: key, maximumCount: 2)

        #expect(store.recentPaths == ["/tmp/First", "/tmp/Second"])
        #expect(userDefaults.stringArray(forKey: key) == store.recentPaths)
    }

    @Test func ignoresNonFileURLsAndRemovesNormalizedPaths() {
        let store = RecentLocationStore(userDefaults: makeUserDefaults())
        store.record(URL(string: "https://example.com/path")!)
        store.record(URL(filePath: "/tmp/Parent/../Recent", directoryHint: .isDirectory))

        #expect(store.recentPaths == ["/tmp/Recent"])

        store.remove(path: "/tmp/Other/../Recent")
        #expect(store.recentPaths.isEmpty)
    }

    @Test func malformedDefaultsAreRemoved() {
        let userDefaults = makeUserDefaults()
        let key = "Recent"
        userDefaults.set([1, 2, 3], forKey: key)

        let store = RecentLocationStore(userDefaults: userDefaults, key: key)

        #expect(store.recentPaths.isEmpty)
        #expect(userDefaults.object(forKey: key) == nil)
    }

    private func makeUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: "OpenPaneRecentLocationStoreTests-\(UUID().uuidString)")!
    }
}
