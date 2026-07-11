//
//  PerformanceDiagnostics.swift
//  OpenPane
//

#if DEBUG
import Foundation

nonisolated struct PerformanceDiagnosticsSnapshot: Equatable, Sendable {
    let visibleItemComputations: Int
    let visibleItemPublications: Int
    let directoryEnumerations: Int
    let iconCacheMisses: Int
    let itemArrayReplacements: Int
    let dualPaneChangeFanouts: Int
}

nonisolated final class PerformanceDiagnostics: @unchecked Sendable {
    static let shared = PerformanceDiagnostics()

    private let lock = NSLock()
    private var visibleItemComputations = 0
    private var visibleItemPublications = 0
    private var directoryEnumerations = 0
    private var iconCacheMisses = 0
    private var itemArrayReplacements = 0
    private var dualPaneChangeFanouts = 0

    private init() {}

    func recordVisibleItemComputation() {
        lock.withLock { visibleItemComputations += 1 }
    }

    func recordVisibleItemPublication() {
        lock.withLock { visibleItemPublications += 1 }
    }

    func recordDirectoryEnumeration() {
        lock.withLock { directoryEnumerations += 1 }
    }

    func recordIconCacheMiss() {
        lock.withLock { iconCacheMisses += 1 }
    }

    func recordItemArrayReplacement() {
        lock.withLock { itemArrayReplacements += 1 }
    }

    func recordDualPaneChangeFanout() {
        lock.withLock { dualPaneChangeFanouts += 1 }
    }

    func reset() {
        lock.withLock {
            visibleItemComputations = 0
            visibleItemPublications = 0
            directoryEnumerations = 0
            iconCacheMisses = 0
            itemArrayReplacements = 0
            dualPaneChangeFanouts = 0
        }
    }

    func snapshot() -> PerformanceDiagnosticsSnapshot {
        lock.withLock {
            PerformanceDiagnosticsSnapshot(
                visibleItemComputations: visibleItemComputations,
                visibleItemPublications: visibleItemPublications,
                directoryEnumerations: directoryEnumerations,
                iconCacheMisses: iconCacheMisses,
                itemArrayReplacements: itemArrayReplacements,
                dualPaneChangeFanouts: dualPaneChangeFanouts
            )
        }
    }
}
#endif
