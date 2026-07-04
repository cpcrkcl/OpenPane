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
