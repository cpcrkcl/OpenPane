//
//  FileIconServiceTests.swift
//  OpenPaneTests
//
//  Created by Codex on 7/3/26.
//

import Foundation
import Testing
@testable import OpenPane

@MainActor
struct FileIconServiceTests {
    @Test func sameFileExtensionReturnsCachedIconInstance() throws {
        let temporaryDirectory = try IconTestTemporaryDirectory()
        let firstItem = try temporaryDirectory.createFileItem(named: "first.txt")
        let secondItem = try temporaryDirectory.createFileItem(named: "second.txt")
        let service = FileIconService()

        let firstIcon = service.icon(for: firstItem)
        let secondIcon = service.icon(for: secondItem)

        #expect(firstIcon === secondIcon)
    }

    @Test func directoryIconsUseStableCachedIconInstance() throws {
        let temporaryDirectory = try IconTestTemporaryDirectory()
        let firstDirectory = try temporaryDirectory.createDirectoryItem(named: "First")
        let secondDirectory = try temporaryDirectory.createDirectoryItem(named: "Second")
        let service = FileIconService()

        let firstIcon = service.icon(for: firstDirectory)
        let secondIcon = service.icon(for: secondDirectory)

        #expect(firstIcon === secondIcon)
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
