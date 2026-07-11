//
//  PerformanceBenchmarkTests.swift
//  OpenPaneTests
//
//  Reproducible performance probe. Run it in isolation with xcodebuild's
//  -only-testing:OpenPaneTests/PerformanceBenchmarkTests option. The latest
//  metrics are written to /tmp/OpenPanePerformanceBenchmark.json.
//

import Foundation
import Testing
@testable import OpenPane

@MainActor
struct PerformanceBenchmarkTests {
    @Test func tenThousandFileDirectoryPipeline() async throws {
        let fileCount = 10_000
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPanePerformanceBenchmarks", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        for index in 0..<fileCount {
            let fileURL = directoryURL.appendingPathComponent(
                String(format: "sample-%05d.txt", index)
            )
            #expect(FileManager.default.createFile(atPath: fileURL.path, contents: nil))
        }

        let directoryMonitorService = BenchmarkDirectoryMonitorService()
        let viewModel = FilePaneViewModel(
            currentURL: directoryURL,
            fileBrowserService: FileBrowserService(),
            directoryMonitorService: directoryMonitorService,
            directoryRefreshDebounceNanoseconds: 10_000_000,
            visibleItemsSearchDebounceNanoseconds: 0
        )
        let start = ProcessInfo.processInfo.systemUptime
        let loadTask = Task { await viewModel.loadCurrentDirectory() }

        try await waitUntil { viewModel.items.count == fileCount }
        let firstItemsMilliseconds = milliseconds(since: start)

        try await waitUntil { viewModel.visibleItems.count == fileCount }
        let firstVisibleItemsMilliseconds = milliseconds(since: start)

        await loadTask.value
        await viewModel.waitForMetadataEnrichment()
        let metadataReadyMilliseconds = milliseconds(since: start)

        let itemPublicationCount = viewModel.itemsPublicationCount
        let monitorStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<5 {
            directoryMonitorService.emitChange()
        }
        try await waitUntil { viewModel.directoryFingerprintCheckCount == 1 }
        let noOpMonitorMilliseconds = milliseconds(since: monitorStart)

        let searchStart = ProcessInfo.processInfo.systemUptime
        let searchResults = try await FileSearchService().search(
            root: directoryURL,
            query: "sample-09999",
            includeHiddenFiles: false,
            limit: 500
        )
        let singleMatchSearchMilliseconds = milliseconds(since: searchStart)

        #expect(viewModel.items.count == fileCount)
        #expect(viewModel.items.allSatisfy { $0.hasExtendedMetadata })
        #expect(viewModel.directoryFingerprintNoOpCount == 1)
        #expect(viewModel.itemsPublicationCount == itemPublicationCount)
        #expect(searchResults.map(\.name) == ["sample-09999.txt"])
        let metrics = [
            "first_items_ms": firstItemsMilliseconds,
            "first_visible_ms": firstVisibleItemsMilliseconds,
            "metadata_ready_ms": metadataReadyMilliseconds,
            "noop_monitor_burst_ms": noOpMonitorMilliseconds,
            "recursive_single_match_ms": singleMatchSearchMilliseconds
        ]
        let metricsData = try JSONSerialization.data(
            withJSONObject: metrics,
            options: [.prettyPrinted, .sortedKeys]
        )
        try metricsData.write(
            to: URL(fileURLWithPath: "/tmp/OpenPanePerformanceBenchmark.json"),
            options: .atomic
        )
        print(
            "OPENPANE_BENCHMARK " +
            "first_items_ms=\(format(firstItemsMilliseconds)) " +
            "first_visible_ms=\(format(firstVisibleItemsMilliseconds)) " +
            "metadata_ready_ms=\(format(metadataReadyMilliseconds)) " +
            "noop_monitor_burst_ms=\(format(noOpMonitorMilliseconds)) " +
            "recursive_single_match_ms=\(format(singleMatchSearchMilliseconds))"
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 10,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                Issue.record("Timed out waiting for the benchmark publication")
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func milliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

nonisolated private final class BenchmarkDirectoryMonitorService: DirectoryMonitorServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var onChange: (@Sendable () -> Void)?

    nonisolated func monitorDirectory(
        at url: URL,
        onChange: @escaping @Sendable () -> Void
    ) -> any DirectoryMonitorToken {
        lock.withLock { self.onChange = onChange }
        return BenchmarkDirectoryMonitorToken()
    }

    nonisolated func emitChange() {
        let callback = lock.withLock { onChange }
        callback?()
    }
}

nonisolated private final class BenchmarkDirectoryMonitorToken: DirectoryMonitorToken, @unchecked Sendable {
    nonisolated func cancel() {}
}
