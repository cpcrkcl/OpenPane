//
//  FolderSizeServiceTests.swift
//  OpenPaneTests
//
//  Created by Codex on 7/3/26.
//

import Foundation
import Testing
@testable import OpenPane

struct FolderSizeServiceTests {
    @Test func calculatesNestedFolderSizeCorrectly() async throws {
        let temporaryDirectory = try FolderSizeTestTemporaryDirectory()
        try temporaryDirectory.writeFile(named: "one.bin", byteCount: 5)
        try temporaryDirectory.writeFile(named: "Nested/two.bin", byteCount: 7)

        let result = try await FolderSizeService().size(of: temporaryDirectory.url)

        #expect(result.byteCount == 12)
        #expect(result.skippedItemCount == 0)
    }

    @Test func includesHiddenFilesInFolderSize() async throws {
        let temporaryDirectory = try FolderSizeTestTemporaryDirectory()
        try temporaryDirectory.writeFile(named: "visible.bin", byteCount: 5)
        try temporaryDirectory.writeFile(named: ".hidden.bin", byteCount: 7)

        let result = try await FolderSizeService().size(of: temporaryDirectory.url)

        #expect(result.byteCount == 12)
        #expect(result.skippedItemCount == 0)
    }

    @Test func avoidsFollowingSymlinkLoops() async throws {
        let temporaryDirectory = try FolderSizeTestTemporaryDirectory()
        try temporaryDirectory.writeFile(named: "file.bin", byteCount: 3)
        let nestedURL = try temporaryDirectory.createDirectory(named: "Nested")
        try FileManager.default.createSymbolicLink(
            at: nestedURL.appendingPathComponent("Loop", isDirectory: true),
            withDestinationURL: temporaryDirectory.url
        )

        let result = try await FolderSizeService().size(of: temporaryDirectory.url)

        #expect(result.byteCount == 3)
    }

    @Test func cancellationStopsCalculation() async throws {
        let temporaryDirectory = try FolderSizeTestTemporaryDirectory()

        for index in 0..<2_000 {
            try temporaryDirectory.writeFile(named: "file-\(index).bin", byteCount: 1)
        }

        let service = FolderSizeService()
        let task = Task {
            try await service.size(of: temporaryDirectory.url)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test func cachedResultIsReusedUntilInvalidated() async throws {
        let temporaryDirectory = try FolderSizeTestTemporaryDirectory()
        try temporaryDirectory.writeFile(named: "file.bin", byteCount: 4)
        let service = FolderSizeService()

        let firstResult = try await service.size(of: temporaryDirectory.url)
        try temporaryDirectory.writeFile(named: "file.bin", byteCount: 9)
        let cachedResult = try await service.size(of: temporaryDirectory.url)
        service.invalidate(temporaryDirectory.url)
        let recalculatedResult = try await service.size(of: temporaryDirectory.url)

        #expect(firstResult.byteCount == 4)
        #expect(cachedResult.byteCount == 4)
        #expect(recalculatedResult.byteCount == 9)
    }

    @Test func cacheUsesBoundedLRUEviction() async throws {
        let temporaryDirectory = try FolderSizeTestTemporaryDirectory()
        let firstURL = try temporaryDirectory.createDirectory(named: "First")
        let secondURL = try temporaryDirectory.createDirectory(named: "Second")
        let thirdURL = try temporaryDirectory.createDirectory(named: "Third")
        try temporaryDirectory.writeFile(named: "First/file.bin", byteCount: 1)
        try temporaryDirectory.writeFile(named: "Second/file.bin", byteCount: 2)
        try temporaryDirectory.writeFile(named: "Third/file.bin", byteCount: 3)
        let service = FolderSizeService(maximumCacheEntryCount: 2)

        _ = try await service.size(of: firstURL)
        _ = try await service.size(of: secondURL)
        _ = try await service.size(of: thirdURL)

        #expect(service.cachedResultCount == 2)
        #expect(service.cachedSize(of: firstURL) == nil)
        #expect(service.cachedSize(of: secondURL)?.byteCount == 2)
        #expect(service.cachedSize(of: thirdURL)?.byteCount == 3)
    }

    @Test func cachedReadDoesNotRequireTheFolderToStillExist() async throws {
        let temporaryDirectory = try FolderSizeTestTemporaryDirectory()
        let cachedDirectoryURL = try temporaryDirectory.createDirectory(named: "Cached")
        try temporaryDirectory.writeFile(named: "Cached/file.bin", byteCount: 5)
        let service = FolderSizeService()

        _ = try await service.size(of: cachedDirectoryURL)
        try FileManager.default.removeItem(at: cachedDirectoryURL)

        #expect(service.cachedSize(of: cachedDirectoryURL)?.byteCount == 5)
    }

    @Test func invalidationDuringCalculationDoesNotPublishStaleCacheEntry() async throws {
        let temporaryDirectory = try FolderSizeTestTemporaryDirectory()
        let calculation = SuspendedFolderSizeCalculation()
        let service = FolderSizeService(calculation: calculation.calculate)

        let request = Task {
            try await service.size(of: temporaryDirectory.url)
        }
        await calculation.waitUntilStarted()
        service.invalidate(temporaryDirectory.url)
        await calculation.finish(
            with: FolderSizeResult(byteCount: 123, skippedItemCount: 0)
        )

        await #expect(throws: CancellationError.self) {
            _ = try await request.value
        }
        #expect(service.cachedSize(of: temporaryDirectory.url) == nil)
    }
}

private actor SuspendedFolderSizeCalculation {
    private var hasStarted = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<FolderSizeResult, Never>?

    func calculate(_ url: URL) async -> FolderSizeResult {
        hasStarted = true
        startContinuations.forEach { $0.resume() }
        startContinuations.removeAll()

        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func finish(with result: FolderSizeResult) {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}

private struct FolderSizeTestTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneFolderSizeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createDirectory(named relativePath: String) throws -> URL {
        let directoryURL = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    func writeFile(named relativePath: String, byteCount: Int) throws {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 7, count: byteCount).write(to: fileURL)
    }
}
