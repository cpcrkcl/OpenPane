//
//  FileItem.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modifiedDate: Date?
    let typeIdentifier: String?
    let isHidden: Bool

    init(url: URL) throws {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .typeIdentifierKey,
            .isHiddenKey
        ]
        let resourceValues = try url.resourceValues(forKeys: resourceKeys)
        let isDirectory = resourceValues.isDirectory ?? false

        self.id = url
        self.url = url
        self.name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        self.isDirectory = isDirectory
        self.size = isDirectory ? nil : Self.fileSize(from: resourceValues)
        self.modifiedDate = resourceValues.contentModificationDate
        self.typeIdentifier = resourceValues.typeIdentifier
        self.isHidden = resourceValues.isHidden ?? false
    }

    var displayName: String {
        name
    }

    var formattedSize: String {
        guard let size else {
            return "Folder"
        }

        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedModifiedDate: String {
        guard let modifiedDate else {
            return ""
        }

        return modifiedDate.formatted(date: .abbreviated, time: .shortened)
    }

    var kindDescription: String {
        if let typeIdentifier,
           let type = UTType(typeIdentifier),
           let localizedDescription = type.localizedDescription {
            return localizedDescription
        }

        return isDirectory ? "Folder" : "File"
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
