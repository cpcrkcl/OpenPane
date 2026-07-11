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

        let viewModel = FilePaneViewModel(
            currentURL: directoryURL,
            fileBrowserService: FileBrowserService(),
            directoryMonitorService: NoopDirectoryMonitoringService(),
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

        #expect(viewModel.items.count == fileCount)
        #expect(viewModel.items.allSatisfy { $0.hasExtendedMetadata })
        let metrics = [
            "first_items_ms": firstItemsMilliseconds,
            "first_visible_ms": firstVisibleItemsMilliseconds,
            "metadata_ready_ms": metadataReadyMilliseconds
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
            "metadata_ready_ms=\(format(metadataReadyMilliseconds))"
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
