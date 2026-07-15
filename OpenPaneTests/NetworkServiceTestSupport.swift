//
//  NetworkServiceTestSupport.swift
//  OpenPaneTests
//
//  Created by Codex on 7/11/26.
//

import Foundation
@testable import OpenPane

nonisolated final class FakeNetworkDiscoveryService: NetworkDiscovering, @unchecked Sendable {
    let stream: AsyncThrowingStream<[DiscoveredNetworkServer], Error>

    init(stream: AsyncThrowingStream<[DiscoveredNetworkServer], Error>) {
        self.stream = stream
    }

    nonisolated func browseSMBServices() -> AsyncThrowingStream<[DiscoveredNetworkServer], Error> {
        stream
    }
}

nonisolated final class FakeNetworkMountService: NetworkMounting, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<[URL], Error>
    private var protectedRequestedURLs: [URL] = []

    init(result: Result<[URL], Error>) {
        self.result = result
    }

    nonisolated var requestedURLs: [URL] {
        lock.withLock {
            protectedRequestedURLs
        }
    }

    nonisolated func mount(serverURL: URL) async throws -> [URL] {
        lock.withLock {
            protectedRequestedURLs.append(serverURL)
        }

        return try result.get()
    }
}
