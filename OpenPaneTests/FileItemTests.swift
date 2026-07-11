//
//  FileItemTests.swift
//  OpenPaneTests
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation
import Testing
@testable import OpenPane

struct FileItemTests {
    @Test func essentialInitializerDefersOptionalMetadataAndFormatting() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let fileURL = temporaryDirectory.url.appendingPathComponent("lightweight.txt")
        try Data("contents".utf8).write(to: fileURL)

        let item = try FileItem(essentialURL: fileURL)

        #expect(item.name == "lightweight.txt")
        #expect(!item.isDirectory)
        #expect(!item.hasExtendedMetadata)
        #expect(item.size == nil)
        #expect(item.modifiedDate == nil)
        #expect(item.kindDescription == "File")
    }

    @Test func readsFileMetadata() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let fileURL = temporaryDirectory.url.appendingPathComponent("example.txt")
        let data = Data("OpenPane".utf8)

        let didCreateFile = FileManager.default.createFile(atPath: fileURL.path, contents: data)
        #expect(didCreateFile)

        let item = try FileItem(url: fileURL)

        #expect(item.id == fileURL)
        #expect(item.url == fileURL)
        #expect(item.name == "example.txt")
        #expect(item.displayName == "example.txt")
        #expect(item.isDirectory == false)
        #expect(item.size == Int64(data.count))
        #expect(item.isHidden == false)
        #expect(item.modifiedDate != nil)
    }

    @Test func readsDirectoryMetadata() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let directoryURL = temporaryDirectory.url.appendingPathComponent("Folder")

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        let item = try FileItem(url: directoryURL)

        #expect(item.name == "Folder")
        #expect(item.isDirectory)
        #expect(item.size == nil)
        #expect(item.modifiedDate != nil)
    }

    @Test func detectsHiddenFiles() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let fileURL = temporaryDirectory.url.appendingPathComponent(".hidden")

        let didCreateFile = FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        #expect(didCreateFile)

        let item = try FileItem(url: fileURL)

        #expect(item.name == ".hidden")
        #expect(item.isHidden)
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
