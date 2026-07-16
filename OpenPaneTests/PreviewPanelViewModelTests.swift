//
//  PreviewPanelViewModelTests.swift
//  OpenPaneTests
//

import AppKit
import Foundation
import Testing
@testable import OpenPane

@MainActor
struct PreviewPanelViewModelTests {
    @Test func latestSelectionWinsWhenEarlierMetadataFinishesLater() async throws {
        let directory = try PreviewPanelTestDirectory()
        let first = try directory.item(named: "first.txt", contents: "first")
        let second = try directory.item(named: "second.txt", contents: "second")
        let metadataService = PreviewPanelMetadataService(delays: [
            first.url: 150_000_000,
            second.url: 1_000_000
        ])
        let viewModel = PreviewPanelViewModel(
            metadataService: metadataService,
            textEditingService: PreviewPanelTextService(),
            fileIconService: PreviewPanelIconService()
        )

        viewModel.select(FilePreviewTarget(paneSide: .left, item: first))
        viewModel.select(FilePreviewTarget(paneSide: .left, item: second))
        await waitUntil { viewModel.metadata?.url == second.url }
        try await Task.sleep(nanoseconds: 180_000_000)

        #expect(viewModel.target?.item == second)
        #expect(viewModel.metadata?.url == second.url)
    }

    @Test func coreMetadataPublishesBeforeDeferredFormatDetails() async throws {
        let directory = try PreviewPanelTestDirectory()
        let item = try directory.item(named: "track.txt", contents: "track")
        let metadataService = PreviewPanelMetadataService(
            enrichmentDelay: 150_000_000,
            enrichmentDetails: .audio(duration: 12)
        )
        let viewModel = PreviewPanelViewModel(
            metadataService: metadataService,
            textEditingService: PreviewPanelTextService(),
            fileIconService: PreviewPanelIconService()
        )

        viewModel.select(FilePreviewTarget(paneSide: .left, item: item))
        await waitUntil { viewModel.metadata?.url == item.url }

        #expect(viewModel.metadata?.formatDetails == nil)
        await waitUntil { viewModel.metadata?.formatDetails != nil }
        #expect(viewModel.metadata?.formatDetails == .audio(duration: 12))
    }

    @Test func dirtyEditorDefersSelectionAndKeepsOnlyLatestTarget() async throws {
        let directory = try PreviewPanelTestDirectory()
        let first = try directory.item(named: "first.txt", contents: "first")
        let second = try directory.item(named: "second.txt", contents: "second")
        let third = try directory.item(named: "third.txt", contents: "third")
        let viewModel = PreviewPanelViewModel(
            metadataService: PreviewPanelMetadataService(),
            textEditingService: PreviewPanelTextService(),
            fileIconService: PreviewPanelIconService()
        )

        viewModel.select(FilePreviewTarget(paneSide: .left, item: first))
        await waitUntil { viewModel.canBeginEditing }
        viewModel.beginEditing()
        await waitUntil { viewModel.editorBuffer != nil }
        viewModel.editorBuffer?.textStorage.append(NSAttributedString(string: " edited"))
        await waitUntil { viewModel.isDirty }

        viewModel.select(FilePreviewTarget(paneSide: .right, item: second))
        viewModel.select(FilePreviewTarget(paneSide: .right, item: third))

        #expect(viewModel.target?.item == first)
        #expect(viewModel.pendingTransition == .select(FilePreviewTarget(paneSide: .right, item: third)))

        viewModel.discardChanges()
        #expect(viewModel.target?.item == third)
        #expect(!viewModel.isEditing)
        #expect(!viewModel.isDirty)
    }

    @Test func dirtyClosePublishesResolutionOnlyAfterDiscard() async throws {
        let directory = try PreviewPanelTestDirectory()
        let item = try directory.item(named: "notes.txt", contents: "notes")
        let viewModel = PreviewPanelViewModel(
            metadataService: PreviewPanelMetadataService(),
            textEditingService: PreviewPanelTextService(),
            fileIconService: PreviewPanelIconService()
        )

        viewModel.select(FilePreviewTarget(paneSide: .left, item: item))
        await waitUntil { viewModel.canBeginEditing }
        viewModel.beginEditing()
        await waitUntil { viewModel.editorBuffer != nil }
        viewModel.editorBuffer?.textStorage.append(NSAttributedString(string: " edited"))
        await waitUntil { viewModel.isDirty }

        #expect(!viewModel.requestClose())
        #expect(viewModel.resolvedCloseRequestCount == 0)
        #expect(viewModel.unsavedChangesPrompt == .transition(.close))

        viewModel.discardChanges()
        #expect(viewModel.resolvedCloseRequestCount == 1)
        #expect(!viewModel.isDirty)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        attempts: Int = 500
    ) async {
        for _ in 0..<attempts {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Timed out waiting for preview state")
    }
}

private struct PreviewPanelTestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPanePreviewPanelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func item(named name: String, contents: String) throws -> FileItem {
        let fileURL = url.appendingPathComponent(name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileItem(url: fileURL)
    }
}

private nonisolated final class PreviewPanelMetadataService: FilePreviewMetadataServicing, @unchecked Sendable {
    private let delays: [URL: UInt64]
    private let enrichmentDelay: UInt64?
    private let enrichmentDetails: FileFormatDetails?

    nonisolated init(
        delays: [URL: UInt64] = [:],
        enrichmentDelay: UInt64? = nil,
        enrichmentDetails: FileFormatDetails? = nil
    ) {
        self.delays = delays
        self.enrichmentDelay = enrichmentDelay
        self.enrichmentDetails = enrichmentDetails
    }

    nonisolated func enrichedMetadata(for metadata: FilePreviewMetadata) async throws -> FilePreviewMetadata {
        if let enrichmentDelay {
            try await Task.sleep(nanoseconds: enrichmentDelay)
        }
        try Task.checkCancellation()
        return metadata.replacingFormatDetails(enrichmentDetails)
    }

    nonisolated func metadata(for url: URL) async throws -> FilePreviewMetadata {
        if let delay = delays[url] {
            try await Task.sleep(nanoseconds: delay)
        }
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value
        let modified = attributes[.modificationDate] as? Date
        return FilePreviewMetadata(
            url: url,
            revision: FilePreviewRevision(
                resourceIdentifier: url.path,
                logicalSize: size,
                contentModificationDate: modified
            ),
            name: url.lastPathComponent,
            kindDescription: "Plain Text",
            fileExtension: url.pathExtension,
            typeIdentifier: "public.plain-text",
            mimeType: "text/plain",
            fullPath: url.path,
            parentPath: url.deletingLastPathComponent().path,
            volumeName: nil,
            volumeKind: .local,
            symbolicLinkTarget: nil,
            creationDate: attributes[.creationDate] as? Date,
            contentModificationDate: modified,
            attributeModificationDate: nil,
            contentAccessDate: nil,
            addedToDirectoryDate: nil,
            logicalSize: size,
            allocatedSize: size,
            ownerAccountName: nil,
            groupOwnerAccountName: nil,
            posixPermissions: nil,
            isReadable: true,
            isWritable: true,
            isExecutable: false,
            finderTags: [],
            isDirectory: false,
            isPackage: false,
            isSymbolicLink: false,
            formatDetails: nil
        )
    }

    nonisolated func cachedMetadata(for url: URL, revision: FilePreviewRevision) -> FilePreviewMetadata? {
        nil
    }

    nonisolated func invalidate(_ url: URL) {}
}

private nonisolated struct PreviewPanelTextService: TextFileEditingServicing {
    nonisolated func inspect(url: URL) async -> TextEditEligibility {
        .eligible
    }

    nonisolated func load(url: URL) async throws -> EditableTextDocument {
        EditableTextDocument(
            url: url,
            text: try String(contentsOf: url, encoding: .utf8),
            encoding: .utf8(hasByteOrderMark: false),
            fingerprint: TextFileFingerprint(
                deviceID: 1,
                fileID: 1,
                byteCount: 1,
                modificationSeconds: 1,
                modificationNanoseconds: 0
            )
        )
    }

    nonisolated func save(
        document: EditableTextDocument,
        text: String,
        conflictPolicy: TextSaveConflictPolicy
    ) async throws -> EditableTextDocument {
        EditableTextDocument(
            url: document.url,
            text: text,
            encoding: document.encoding,
            fingerprint: TextFileFingerprint(
                deviceID: 1,
                fileID: 1,
                byteCount: Int64(text.utf8.count),
                modificationSeconds: 2,
                modificationNanoseconds: 0
            )
        )
    }
}

@MainActor
private final class PreviewPanelIconService: FileIconServicing {
    func cachedIcon(for item: FileItem) -> NSImage? {
        nil
    }

    func icon(for item: FileItem) async -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16))
    }
}
