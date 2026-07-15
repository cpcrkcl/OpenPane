//
//  NetworkDiscoveryService.swift
//  OpenPane
//
//  Created by Codex on 7/11/26.
//

import Foundation
@preconcurrency import Network

nonisolated enum NetworkDiscoveryError: LocalizedError, Equatable, Sendable {
    case permissionDenied
    case browserFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Local Network permission is denied. Allow OpenPane to discover nearby SMB servers in System Settings > Privacy & Security > Local Network."
        case .browserFailed(let reason):
            return "Network discovery failed: \(reason)"
        }
    }
}

nonisolated protocol NetworkDiscovering: Sendable {
    nonisolated func browseSMBServices() -> AsyncThrowingStream<[DiscoveredNetworkServer], Error>
}

/// Best-effort Bonjour discovery for advertised SMB services on the local
/// network. The stream is live: it yields the complete deduplicated result set
/// whenever Bonjour reports a change, and its lifetime owns the NWBrowser.
nonisolated struct NetworkDiscoveryService: NetworkDiscovering {
    static let smbServiceType = "_smb._tcp"
    static let localDomain = "local"

    private let serviceType: String
    private let domain: String?
    private let queue: DispatchQueue

    nonisolated init(
        serviceType: String = NetworkDiscoveryService.smbServiceType,
        domain: String? = NetworkDiscoveryService.localDomain,
        queue: DispatchQueue = DispatchQueue(
            label: "com.openpane.network-discovery",
            qos: .userInitiated
        )
    ) {
        self.serviceType = serviceType
        self.domain = domain
        self.queue = queue
    }

    nonisolated func browseSMBServices() -> AsyncThrowingStream<[DiscoveredNetworkServer], Error> {
        AsyncThrowingStream { continuation in
            let browser = NWBrowser(
                for: .bonjour(type: serviceType, domain: domain),
                using: NWParameters()
            )

            browser.browseResultsChangedHandler = { results, _ in
                continuation.yield(Self.servers(from: results))
            }

            browser.stateUpdateHandler = { state in
                switch state {
                case .setup:
                    break
                case .ready:
                    continuation.yield(Self.servers(from: browser.browseResults))
                case .waiting(let error):
                    continuation.yield([])
                    // `waiting` is normally recoverable (for example while an
                    // interface is changing), so keep the browser and stream
                    // alive. A denied Local Network permission is terminal
                    // until the user changes it in System Settings.
                    let discoveryError = Self.discoveryError(for: error)
                    if discoveryError == .permissionDenied {
                        continuation.finish(throwing: discoveryError)
                    }
                case .failed(let error):
                    continuation.finish(throwing: Self.discoveryError(for: error))
                case .cancelled:
                    continuation.finish()
                @unknown default:
                    break
                }
            }

            continuation.onTermination = { @Sendable _ in
                browser.cancel()
            }

            browser.start(queue: queue)
        }
    }

    private nonisolated static func servers(
        from results: Set<NWBrowser.Result>
    ) -> [DiscoveredNetworkServer] {
        var serversByID: [String: DiscoveredNetworkServer] = [:]

        for result in results {
            guard case let .service(name, serviceType, domain, _) = result.endpoint else {
                continue
            }

            let server = DiscoveredNetworkServer(
                name: name,
                serviceType: serviceType,
                domain: domain
            )
            serversByID[server.id] = server
        }

        return deduplicatedServers(from: Array(serversByID.values))
    }

    static func deduplicatedServers(from servers: [DiscoveredNetworkServer]) -> [DiscoveredNetworkServer] {
        var serversByID: [String: DiscoveredNetworkServer] = [:]
        for server in servers {
            serversByID[server.id] = server
        }

        return serversByID.values.sorted {
            let nameComparison = $0.displayName.localizedStandardCompare($1.displayName)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }

    private nonisolated static func discoveryError(for error: NWError) -> NetworkDiscoveryError {
        if case .posix(let code) = error,
           code == .EACCES || code == .EPERM {
            return .permissionDenied
        }

        let description = error.localizedDescription.lowercased()
        if description.contains("permission") || description.contains("denied") {
            return .permissionDenied
        }

        return .browserFailed(error.localizedDescription)
    }
}
