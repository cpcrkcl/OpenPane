//
//  FileItem.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation
import UniformTypeIdentifiers

nonisolated struct FileItem: Identifiable, Hashable, Sendable {
    static var essentialResourceKeys: Set<URLResourceKey> {
        [
            .isDirectoryKey,
            .isHiddenKey
        ]
    }

    static var resourceKeys: Set<URLResourceKey> {
        [
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .typeIdentifierKey,
            .isHiddenKey
        ]
    }

    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modifiedDate: Date?
    let typeIdentifier: String?
    let isHidden: Bool
    let kindDescription: String
    let hasExtendedMetadata: Bool

    init(essentialURL url: URL) throws {
        let resourceValues = try url.resourceValues(forKeys: Self.essentialResourceKeys)
        let isDirectory = resourceValues.isDirectory ?? false

        self.id = url
        self.url = url
        self.name = url.openPaneDisplayName
        self.isDirectory = isDirectory
        self.size = nil
        self.modifiedDate = nil
        self.typeIdentifier = nil
        self.isHidden = resourceValues.isHidden ?? false
        self.kindDescription = isDirectory ? "Folder" : "File"
        self.hasExtendedMetadata = false
    }

    init(url: URL) throws {
        let resourceValues = try url.resourceValues(forKeys: Self.resourceKeys)
        let isDirectory = resourceValues.isDirectory ?? false
        let size = isDirectory ? nil : Self.fileSize(from: resourceValues)
        let typeIdentifier = resourceValues.typeIdentifier
        let modifiedDate = resourceValues.contentModificationDate

        self.id = url
        self.url = url
        self.name = url.openPaneDisplayName
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedDate = modifiedDate
        self.typeIdentifier = typeIdentifier
        self.isHidden = resourceValues.isHidden ?? false
        self.kindDescription = Self.kindDescription(for: typeIdentifier, isDirectory: isDirectory)
        self.hasExtendedMetadata = true
    }

    var displayName: String {
        name
    }

    var formattedSize: String {
        Self.formattedSize(for: size, isDirectory: isDirectory)
    }

    var formattedModifiedDate: String {
        Self.formattedModifiedDate(for: modifiedDate)
    }

    private static func formattedSize(for size: Int64?, isDirectory: Bool) -> String {
        guard let size,
              !isDirectory else {
            return "Folder"
        }

        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private static func formattedModifiedDate(for modifiedDate: Date?) -> String {
        guard let modifiedDate else {
            return ""
        }

        return modifiedDate.formatted(date: .abbreviated, time: .shortened)
    }

    private static func kindDescription(for typeIdentifier: String?, isDirectory: Bool) -> String {
        if let typeIdentifier,
           let type = UTType(typeIdentifier),
           let localizedDescription = type.localizedDescription {
            return localizedDescription
        }

        return isDirectory ? "Folder" : "File"
    }

    var sortSize: Int64 {
        size ?? -1
    }

    var sortModifiedDate: Date {
        modifiedDate ?? .distantPast
    }

    private static func fileSize(from resourceValues: URLResourceValues) -> Int64? {
        if let fileSize = resourceValues.fileSize {
            return Int64(fileSize)
        }

        if let allocatedSize = resourceValues.totalFileAllocatedSize {
            return Int64(allocatedSize)
        }

        return nil
    }
}
