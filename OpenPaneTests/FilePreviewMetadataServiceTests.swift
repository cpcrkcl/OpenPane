//
//  FilePreviewMetadataServiceTests.swift
//  OpenPaneTests
//

import AppKit
import Foundation
import ImageIO
import Testing
@testable import OpenPane

struct FilePreviewMetadataServiceTests {
    @Test func loadsCoreMetadataAndPOSIXPermissions() async throws {
        let directory = try FilePreviewMetadataTestDirectory()
        let fileURL = try directory.write(Data("hello".utf8), named: "Notes.txt")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o640],
            ofItemAtPath: fileURL.path
        )

        let metadata = try await FilePreviewMetadataService().metadata(for: fileURL)

        #expect(metadata.url == fileURL.standardizedFileURL)
        #expect(metadata.name == "Notes.txt")
        #expect(metadata.fileExtension == "txt")
        #expect(metadata.typeIdentifier != nil)
        #expect(metadata.mimeType == "text/plain")
        #expect(metadata.fullPath == fileURL.path)
        #expect(metadata.parentPath == directory.url.path)
        #expect(metadata.logicalSize == 5)
        #expect(metadata.allocatedSize != nil)
        #expect(metadata.creationDate != nil)
        #expect(metadata.contentModificationDate != nil)
        #expect(metadata.ownerAccountName != nil)
        #expect(metadata.groupOwnerAccountName != nil)
        #expect(metadata.posixPermissions.map { $0 & 0o777 } == 0o640)
        #expect(metadata.symbolicPermissions == "rw-r-----")
        #expect(metadata.octalPermissions == "0640")
        #expect(metadata.permissionsDescription == "rw-r----- (0640)")
        #expect(metadata.isDirectory == false)
        #expect(metadata.isPackage == false)
        #expect(metadata.isSymbolicLink == false)
        #expect(metadata.volumeKind == .local)
    }

    @Test func reportsSymlinkTargetWithoutFollowingItForTheLabel() async throws {
        let directory = try FilePreviewMetadataTestDirectory()
        _ = try directory.write(Data("target".utf8), named: "Target.txt")
        let linkURL = directory.url.appendingPathComponent("Shortcut")
        try FileManager.default.createSymbolicLink(
            atPath: linkURL.path,
            withDestinationPath: "Target.txt"
        )

        let metadata = try await FilePreviewMetadataService().metadata(for: linkURL)

        #expect(metadata.isSymbolicLink)
        #expect(metadata.symbolicLinkTarget == "Target.txt")
    }

    @Test func loadsImageDimensionsAndColorModel() async throws {
        let directory = try FilePreviewMetadataTestDirectory()
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 3,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let pngData = try #require(bitmap.representation(using: .png, properties: [:]))
        let imageURL = try directory.write(pngData, named: "Small.png")

        let metadata = try await FilePreviewMetadataService().metadata(for: imageURL)

        guard case .image(let width, let height, let colorModel) = metadata.formatDetails else {
            Issue.record("Expected image format details")
            return
        }
        #expect(width == 3)
        #expect(height == 2)
        #expect(colorModel != nil)
    }

    @Test func loadsApplicationBundleIdentifiersAndVersions() async throws {
        let directory = try FilePreviewMetadataTestDirectory()
        let applicationURL = directory.url.appendingPathComponent("Sample.app", isDirectory: true)
        let contentsURL = applicationURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.Sample",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "45"
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        let metadata = try await FilePreviewMetadataService().metadata(for: applicationURL)

        guard case .application(let identifier, let shortVersion, let buildVersion) = metadata.formatDetails else {
            Issue.record("Expected application format details")
            return
        }
        #expect(identifier == "com.example.Sample")
        #expect(shortVersion == "1.2.3")
        #expect(buildVersion == "45")
    }

    @Test func unavailableMediaDetailsDoNotHideCoreMetadata() async throws {
        let directory = try FilePreviewMetadataTestDirectory()
        let audioURL = try directory.write(Data("not really audio".utf8), named: "Broken.mp3")

        let service = FilePreviewMetadataService()
        let metadata = try await service.metadata(for: audioURL)

        #expect(metadata.name == "Broken.mp3")
        #expect(metadata.logicalSize == 16)
        #expect(metadata.formatDetails == nil)

        let enrichedMetadata = try await service.enrichedMetadata(for: metadata)
        guard case .audio(let duration) = enrichedMetadata.formatDetails else {
            Issue.record("Expected an audio detail placeholder")
            return
        }
        #expect(duration == nil)
    }

    @Test func cacheUsesBoundedLRUEviction() async throws {
        let tracker = FilePreviewMetadataLoaderTracker()
        let service = makeService(maximumCacheEntryCount: 2, tracker: tracker)
        let firstURL = URL(fileURLWithPath: "/tmp/first")
        let secondURL = URL(fileURLWithPath: "/tmp/second")
        let thirdURL = URL(fileURLWithPath: "/tmp/third")

        let first = try await service.metadata(for: firstURL)
        let second = try await service.metadata(for: secondURL)
        _ = service.cachedMetadata(for: firstURL, revision: first.revision)
        let third = try await service.metadata(for: thirdURL)

        #expect(service.cachedMetadataCount == 2)
        #expect(service.cachedMetadata(for: firstURL, revision: first.revision) != nil)
        #expect(service.cachedMetadata(for: secondURL, revision: second.revision) == nil)
        #expect(service.cachedMetadata(for: thirdURL, revision: third.revision) != nil)
        #expect(await tracker.metadataLoadCount == 3)
    }

    @Test func changingRevisionReplacesTheCachedSnapshot() async throws {
        let tracker = FilePreviewMetadataLoaderTracker()
        let service = makeService(maximumCacheEntryCount: 64, tracker: tracker)
        let url = URL(fileURLWithPath: "/tmp/changing")

        let first = try await service.metadata(for: url)
        await tracker.advanceRevision(for: url)
        let second = try await service.metadata(for: url)

        #expect(first.revision != second.revision)
        #expect(service.cachedMetadataCount == 1)
        #expect(service.cachedMetadata(for: url, revision: first.revision) == nil)
        #expect(service.cachedMetadata(for: url, revision: second.revision) != nil)
        #expect(await tracker.metadataLoadCount == 2)
    }

    @Test func explicitInvalidationRemovesAllRevisionsForAURL() async throws {
        let tracker = FilePreviewMetadataLoaderTracker()
        let service = makeService(maximumCacheEntryCount: 64, tracker: tracker)
        let url = URL(fileURLWithPath: "/tmp/invalidate")

        let metadata = try await service.metadata(for: url)
        service.invalidate(url)

        #expect(service.cachedMetadata(for: url, revision: metadata.revision) == nil)
        #expect(service.cachedMetadataCount == 0)
    }

    @Test func cancellationDoesNotPublishOrCacheMetadata() async throws {
        let tracker = FilePreviewMetadataLoaderTracker(suspendsMetadataLoad: true)
        let service = makeService(maximumCacheEntryCount: 64, tracker: tracker)
        let url = URL(fileURLWithPath: "/tmp/cancelled")
        let request = Task {
            try await service.metadata(for: url)
        }

        await tracker.waitUntilMetadataLoadStarts()
        request.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await request.value
        }
        #expect(service.cachedMetadataCount == 0)
    }

    @Test func revisionChangeDuringLoadingRejectsStaleMetadata() async throws {
        let tracker = FilePreviewMetadataLoaderTracker(suspendsMetadataLoad: true)
        let service = makeService(maximumCacheEntryCount: 64, tracker: tracker)
        let url = URL(fileURLWithPath: "/tmp/stale")
        let request = Task {
            try await service.metadata(for: url)
        }

        await tracker.waitUntilMetadataLoadStarts()
        await tracker.advanceRevision(for: url)
        await tracker.finishMetadataLoad()

        await #expect(throws: FilePreviewMetadataError.fileChangedDuringLoad(url.standardizedFileURL)) {
            _ = try await request.value
        }
        #expect(service.cachedMetadataCount == 0)
    }

    private func makeService(
        maximumCacheEntryCount: Int,
        tracker: FilePreviewMetadataLoaderTracker
    ) -> FilePreviewMetadataService {
        FilePreviewMetadataService(
            maximumCacheEntryCount: maximumCacheEntryCount,
            revisionLoader: { url in
                await tracker.revision(for: url)
            },
            metadataLoader: { url, revision in
                try await tracker.metadata(for: url, revision: revision)
            }
        )
    }
}

private actor FilePreviewMetadataLoaderTracker {
    private(set) var metadataLoadCount = 0
    private var revisionGenerationByURL: [URL: Int] = [:]
    private let suspendsMetadataLoad: Bool
    private var metadataLoadStarted = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    init(suspendsMetadataLoad: Bool = false) {
        self.suspendsMetadataLoad = suspendsMetadataLoad
    }

    func revision(for url: URL) -> FilePreviewRevision {
        let generation = revisionGenerationByURL[url, default: 0]
        return FilePreviewRevision(
            resourceIdentifier: "\(url.path)-\(generation)",
            logicalSize: Int64(generation),
            contentModificationDate: Date(timeIntervalSince1970: TimeInterval(generation))
        )
    }

    func metadata(for url: URL, revision: FilePreviewRevision) async throws -> FilePreviewMetadata {
        metadataLoadCount += 1
        metadataLoadStarted = true
        startContinuations.forEach { $0.resume() }
        startContinuations.removeAll()

        if suspendsMetadataLoad {
            try await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    finishContinuation = continuation
                }
                try Task.checkCancellation()
            } onCancel: {
                Task { await self.finishMetadataLoad() }
            }
        }

        return metadataFixture(url: url, revision: revision)
    }

    func advanceRevision(for url: URL) {
        revisionGenerationByURL[url, default: 0] += 1
    }

    func waitUntilMetadataLoadStarts() async {
        guard !metadataLoadStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func finishMetadataLoad() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    private func metadataFixture(url: URL, revision: FilePreviewRevision) -> FilePreviewMetadata {
        FilePreviewMetadata(
            url: url,
            revision: revision,
            name: url.lastPathComponent,
            kindDescription: "File",
            fileExtension: nil,
            typeIdentifier: nil,
            mimeType: nil,
            fullPath: url.path,
            parentPath: url.deletingLastPathComponent().path,
            volumeName: nil,
            volumeKind: .unknown,
            symbolicLinkTarget: nil,
            creationDate: nil,
            contentModificationDate: revision.contentModificationDate,
            attributeModificationDate: nil,
            contentAccessDate: nil,
            addedToDirectoryDate: nil,
            logicalSize: revision.logicalSize,
            allocatedSize: nil,
            ownerAccountName: nil,
            groupOwnerAccountName: nil,
            posixPermissions: nil,
            isReadable: nil,
            isWritable: nil,
            isExecutable: nil,
            finderTags: [],
            isDirectory: false,
            isPackage: false,
            isSymbolicLink: false,
            formatDetails: nil
        )
    }
}

private struct FilePreviewMetadataTestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneFilePreviewMetadataTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ data: Data, named name: String) throws -> URL {
        let fileURL = url.appendingPathComponent(name)
        try data.write(to: fileURL)
        return fileURL
    }
}
