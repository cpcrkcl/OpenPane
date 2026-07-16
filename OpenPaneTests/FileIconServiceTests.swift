//
//  FileIconServiceTests.swift
//  OpenPaneTests
//
//  Created by Codex on 7/3/26.
//

import AppKit
import Foundation
import Testing
@testable import OpenPane

@MainActor
struct FileIconServiceTests {
    @Test func sameFileExtensionReturnsCachedIconInstance() async throws {
        let temporaryDirectory = try IconTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createFileItem(named: "first.txt")
        let secondItem = try temporaryDirectory.createFileItem(named: "second.txt")
        let service = FileIconService()

        let firstIcon = await service.icon(for: firstItem)
        let secondIcon = await service.icon(for: secondItem)

        #expect(firstIcon === secondIcon)
    }

    @Test func directoryIconsUseStableCachedIconInstance() async throws {
        let temporaryDirectory = try IconTestTemporaryDirectory()
        let firstDirectory = try temporaryDirectory.createDirectoryItem(named: "First")
        let secondDirectory = try temporaryDirectory.createDirectoryItem(named: "Second")
        let service = FileIconService()

        let firstIcon = await service.icon(for: firstDirectory)
        let secondIcon = await service.icon(for: secondDirectory)

        #expect(firstIcon === secondIcon)
    }

    @Test func applicationBundlesKeepTheirDistinctIcons() async throws {
        let temporaryDirectory = try IconTestTemporaryDirectory()
        let firstApplication = try temporaryDirectory.createDirectoryItem(named: "First.app")
        let secondApplication = try temporaryDirectory.createDirectoryItem(named: "Second.app")
        let loader = DistinctIconLoader()
        let service = FileIconService(
            observesMemoryPressure: false,
            iconLoader: loader.load
        )

        let firstIcon = await service.icon(for: firstApplication)
        let secondIcon = await service.icon(for: secondApplication)

        #expect(firstIcon !== secondIcon)
        #expect(loader.loadCount == 2)
    }

    @Test func differentDocumentTypesDoNotShareIcons() async throws {
        let temporaryDirectory = try IconTestTemporaryDirectory()
        let wordDocument = try temporaryDirectory.createFileItem(named: "Document.docx")
        let pdfDocument = try temporaryDirectory.createFileItem(named: "Document.pdf")
        let loader = DistinctIconLoader()
        let service = FileIconService(
            observesMemoryPressure: false,
            iconLoader: loader.load
        )

        let wordIcon = await service.icon(for: wordDocument)
        let pdfIcon = await service.icon(for: pdfDocument)

        #expect(wordIcon !== pdfIcon)
        #expect(loader.loadCount == 2)
    }

    @Test func cacheRemainsBoundedAcrossManyExtensions() async throws {
        let temporaryDirectory = try IconTestTemporaryDirectory()
        let service = FileIconService(
            maximumCacheEntryCount: 8,
            maximumCacheCost: 8 * 1_024,
            observesMemoryPressure: false
        )

        for index in 0..<40 {
            let item = try temporaryDirectory.createFileItem(named: "file.type\(index)")
            _ = await service.icon(for: item)
        }

        #expect(service.cachedIconCount == 8)
        #expect(service.cacheLimits.count == 8)
        #expect(service.cacheLimits.cost == 8 * 1_024)
    }

    @Test func concurrentRequestsForSameKeyShareOneLookup() async throws {
        let temporaryDirectory = try IconTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createFileItem(named: "first.dedupe")
        let secondItem = try temporaryDirectory.createFileItem(named: "second.dedupe")
        let loader = CountingIconLoader()
        let service = FileIconService(
            observesMemoryPressure: false,
            iconLoader: loader.load
        )

        async let firstIcon = service.icon(for: firstItem)
        async let secondIcon = service.icon(for: secondItem)
        let icons = await [firstIcon, secondIcon]

        #expect(loader.loadCount == 1)
        #expect(!loader.loadedOnMainThread)
        #expect(icons[0] === icons[1])
        #expect(service.inFlightRequestCount == 0)
    }

    @Test func cacheReadReturnsImmediatelyWithoutStartingAWorkspaceLookup() throws {
        let temporaryDirectory = try IconTestTemporaryDirectory()
        let item = try temporaryDirectory.createFileItem(named: "uncached.read")
        let loader = CountingIconLoader()
        let service = FileIconService(
            observesMemoryPressure: false,
            iconLoader: loader.load
        )

        #expect(service.cachedIcon(for: item) == nil)
        #expect(loader.loadCount == 0)
        #expect(service.inFlightRequestCount == 0)
    }

    @Test func clearingCachePreventsInFlightLookupFromRepopulatingIt() async throws {
        let temporaryDirectory = try IconTestTemporaryDirectory()
        let item = try temporaryDirectory.createFileItem(named: "pending.clear")
        let loader = SuspendedIconLoader()
        let service = FileIconService(
            observesMemoryPressure: false,
            iconLoader: loader.load
        )

        let request = Task { await service.icon(for: item) }
        while service.inFlightRequestCount == 0 || !loader.hasStarted {
            await Task.yield()
        }

        service.removeAllCachedIcons()
        #expect(service.inFlightRequestCount == 0)
        loader.finish()
        _ = await request.value

        #expect(service.cachedIcon(for: item) == nil)
        #expect(service.cachedIconCount == 0)
    }
}

private final class CountingIconLoader: @unchecked Sendable {
    private let lock = NSLock()
    private let loadedIcon: LoadedFileIcon
    private var protectedLoadCount = 0
    private var protectedLoadedOnMainThread = false

    @MainActor
    init() {
        loadedIcon = LoadedFileIcon(
            image: NSImage(size: NSSize(width: 16, height: 16)),
            cost: 1_024
        )
    }

    var loadCount: Int {
        lock.withLock { protectedLoadCount }
    }

    var loadedOnMainThread: Bool {
        lock.withLock { protectedLoadedOnMainThread }
    }

    func load(_ lookup: FileIconLookup) async -> LoadedFileIcon {
        lock.withLock {
            protectedLoadCount += 1
            protectedLoadedOnMainThread = protectedLoadedOnMainThread || Thread.isMainThread
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        return loadedIcon
    }
}

private final class SuspendedIconLoader: @unchecked Sendable {
    private let lock = NSLock()
    private let loadedIcon: LoadedFileIcon
    private var protectedHasStarted = false
    private var continuation: CheckedContinuation<LoadedFileIcon, Never>?

    @MainActor
    init() {
        loadedIcon = LoadedFileIcon(
            image: NSImage(size: NSSize(width: 16, height: 16)),
            cost: 1_024
        )
    }

    var hasStarted: Bool {
        lock.withLock { protectedHasStarted }
    }

    func load(_ lookup: FileIconLookup) async -> LoadedFileIcon {
        await withCheckedContinuation { continuation in
            lock.withLock {
                protectedHasStarted = true
                self.continuation = continuation
            }
        }
    }

    func finish() {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: loadedIcon)
    }
}

private final class DistinctIconLoader: @unchecked Sendable {
    private let lock = NSLock()
    private let icons: [NSImage]
    private var protectedLoadCount = 0

    @MainActor
    init() {
        icons = [
            NSImage(size: NSSize(width: 16, height: 16)),
            NSImage(size: NSSize(width: 17, height: 17))
        ]
    }

    var loadCount: Int {
        lock.withLock { protectedLoadCount }
    }

    func load(_ lookup: FileIconLookup) async -> LoadedFileIcon {
        let image = lock.withLock {
            let image = icons[protectedLoadCount % icons.count]
            protectedLoadCount += 1
            return image
        }
        return LoadedFileIcon(image: image, cost: 1_024)
    }
}

private struct IconTestTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneIconServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createFileItem(named relativePath: String) throws -> FileItem {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("contents".utf8).write(to: fileURL)
        return try FileItem(url: fileURL)
    }

    func createDirectoryItem(named relativePath: String) throws -> FileItem {
        let directoryURL = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return try FileItem(url: directoryURL)
    }
}
