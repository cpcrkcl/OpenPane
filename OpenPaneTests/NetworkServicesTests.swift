//
//  NetworkServicesTests.swift
//  OpenPaneTests
//
//  Created by Codex on 7/11/26.
//

import Foundation
import Testing
@testable import OpenPane

struct NetworkServicesTests {
    @Test func paneLocationsRoundTripThroughCodable() throws {
        let locations: [PaneLocation] = [
            .file(URL(filePath: "/tmp/OpenPane", directoryHint: .isDirectory)),
            .network
        ]

        let decoded = try JSONDecoder().decode(
            [PaneLocation].self,
            from: JSONEncoder().encode(locations)
        )

        #expect(decoded == locations)
        #expect(locations[0].fileURL?.path == "/tmp/OpenPane")
        #expect(locations[1].fileURL == nil)
        #expect(locations[1].displayName == "Network")
        #expect(PaneLocation.networkPlaceholderURL.path == "/Network")
    }

    @Test func normalizesBareHostsAndSMBURLs() throws {
        let bareHost = try NetworkServerAddress.normalize("  SERVER.example/share/  ")
        let explicitURL = try NetworkServerAddress.normalize(
            URL(string: "SMB://SERVER.example/share")!
        )
        let tailscaleAddress = try NetworkServerAddress.normalize("100.64.0.8")

        #expect(bareHost == URL(string: "smb://server.example/share")!)
        #expect(explicitURL == bareHost)
        #expect(tailscaleAddress == URL(string: "smb://100.64.0.8")!)
    }

    @Test func normalizesBareAndBracketedIPv6Addresses() throws {
        let bareAddress = try NetworkServerAddress.normalize("FE80::1/share/")
        let bracketedAddress = try NetworkServerAddress.normalize(
            URL(string: "smb://[FE80::1]/share/")!
        )

        #expect(bareAddress == URL(string: "smb://[fe80::1]/share")!)
        #expect(bracketedAddress == bareAddress)
    }

    @Test func rejectsUnsupportedSchemesCredentialsAndAmbiguousAddresses() throws {
        #expect(throws: NetworkServerAddressError.unsupportedScheme("http")) {
            try NetworkServerAddress.normalize("http://server.example/share")
        }

        #expect(throws: NetworkServerAddressError.credentialsNotAllowed) {
            try NetworkServerAddress.normalize("smb://alice:secret@server.example/share")
        }

        #expect(throws: NetworkServerAddressError.missingHost) {
            try NetworkServerAddress.normalize("smb:///share")
        }

        #expect(throws: NetworkServerAddressError.unsupportedURLComponents) {
            try NetworkServerAddress.normalize("smb://server.example/share?credential=secret")
        }
    }

    @Test func discoveredServersUseServiceIdentityAndSafeSuggestions() {
        let first = DiscoveredNetworkServer(
            name: "Office Server",
            serviceType: "_smb._tcp",
            domain: "local."
        )
        let second = DiscoveredNetworkServer(
            name: "Office Server",
            serviceType: "_SMB._TCP",
            domain: ".LOCAL"
        )
        let credentialBearingSuggestion = DiscoveredNetworkServer(
            name: "Office Server",
            suggestedServerURL: URL(string: "smb://alice:secret@server.example")
        )

        #expect(first.id == second.id)
        #expect(first.suggestedServerURL == URL(string: "smb://office-server.local"))
        #expect(credentialBearingSuggestion.suggestedServerURL == nil)
    }

    @Test func bookmarkNormalizesAndNeverEncodesCredentials() throws {
        let bookmark = try NetworkServerBookmark(
            displayName: "Tailnet NAS",
            address: "server.tailnet-name.ts.net/media/"
        )
        let encoded = try JSONEncoder().encode(bookmark)
        let encodedText = String(decoding: encoded, as: UTF8.self)

        #expect(bookmark.serverURL == URL(string: "smb://server.tailnet-name.ts.net/media")!)
        #expect(!encodedText.localizedCaseInsensitiveContains("password"))
        #expect(!encodedText.localizedCaseInsensitiveContains("secret"))

        #expect(throws: NetworkServerAddressError.credentialsNotAllowed) {
            try NetworkServerBookmark(
                displayName: "Unsafe",
                serverURL: URL(string: "smb://alice:secret@server.example")!
            )
        }
    }

    @Test func bookmarkStorePersistsUpdatesAndRemovals() throws {
        let suiteName = "OpenPaneNetworkBookmarkTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = NetworkServerBookmarkStore(
            userDefaults: userDefaults,
            key: "Bookmarks"
        )
        let first = try NetworkServerBookmark(
            displayName: "Zebra",
            address: "zebra.tailnet.ts.net/share"
        )
        let second = try NetworkServerBookmark(
            displayName: "Alpha",
            address: "100.64.0.4/media"
        )

        store.save(first)
        store.save(second)
        #expect(store.bookmarks.map(\.displayName) == ["Alpha", "Zebra"])

        let restoredStore = NetworkServerBookmarkStore(
            userDefaults: userDefaults,
            key: "Bookmarks"
        )
        #expect(restoredStore.bookmarks == store.bookmarks)

        let updatedFirst = try NetworkServerBookmark(
            displayName: "Updated Zebra",
            serverURL: first.serverURL
        )
        restoredStore.save(updatedFirst)
        #expect(restoredStore.bookmarks.map(\.displayName) == ["Alpha", "Updated Zebra"])

        restoredStore.remove(id: second.id)
        #expect(restoredStore.bookmarks == [updatedFirst])
    }

    @Test func fakeDiscoveryAndMountServicesAreInjectable() async throws {
        let server = DiscoveredNetworkServer(name: "NAS")
        let stream = AsyncThrowingStream<[DiscoveredNetworkServer], Error> { continuation in
            continuation.yield([server])
            continuation.finish()
        }
        let discovery = FakeNetworkDiscoveryService(stream: stream)
        var snapshots: [[DiscoveredNetworkServer]] = []

        for try await snapshot in discovery.browseSMBServices() {
            snapshots.append(snapshot)
        }

        let mountURL = URL(filePath: "/Volumes/NAS", directoryHint: .isDirectory)
        let mounting = FakeNetworkMountService(result: .success([mountURL]))
        let mountedURLs = try await mounting.mount(
            serverURL: URL(string: "smb://nas.local/media")!
        )

        #expect(snapshots == [[server]])
        #expect(mountedURLs == [mountURL])
        #expect(mounting.requestedURLs == [URL(string: "smb://nas.local/media")!])
    }

    @Test func realMountServiceValidatesBeforeCallingNetFS() async throws {
        await #expect(throws: NetworkServerAddressError.credentialsNotAllowed) {
            try await NetworkMountService().mount(
                serverURL: URL(string: "smb://alice:secret@server.example/share")!
            )
        }
    }

    @Test func realMountServiceHonorsPreexistingCancellationBeforeCallingNetFS() async {
        let task = Task { () throws -> [URL] in
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }

            return try await NetworkMountService().mount(
                serverURL: URL(string: "smb://server.example/share")!
            )
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
