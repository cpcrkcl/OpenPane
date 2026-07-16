//
//  FilePreviewModels.swift
//  OpenPane
//
//  Lightweight, value-only models shared by the preview UI and metadata
//  service. Keeping framework objects out of these values makes them safe to
//  move between the metadata worker and the main actor.
//

import Foundation

nonisolated struct FilePreviewRevision: Hashable, Sendable {
    let resourceIdentifier: String?
    let logicalSize: Int64?
    let contentModificationDate: Date?
}

nonisolated struct FilePreviewTarget: Identifiable, Hashable, Sendable {
    let paneSide: PaneSide
    let item: FileItem

    var id: URL { item.id }
}

nonisolated enum FilePreviewVolumeKind: String, Equatable, Sendable {
    case local
    case network
    case unknown
}

nonisolated enum FileFormatDetails: Equatable, Sendable {
    case image(pixelWidth: Int, pixelHeight: Int, colorModel: String?)
    case pdf(pageCount: Int, isEncrypted: Bool)
    case audio(duration: TimeInterval?)
    case video(duration: TimeInterval?, pixelWidth: Int?, pixelHeight: Int?)
    case application(bundleIdentifier: String?, shortVersion: String?, buildVersion: String?)
    case text(encoding: String, hasByteOrderMark: Bool)
}

nonisolated struct FilePreviewMetadata: Equatable, Sendable {
    let url: URL
    let revision: FilePreviewRevision

    let name: String
    let kindDescription: String
    let fileExtension: String?
    let typeIdentifier: String?
    let mimeType: String?
    let fullPath: String
    let parentPath: String
    let volumeName: String?
    let volumeKind: FilePreviewVolumeKind
    let symbolicLinkTarget: String?

    let creationDate: Date?
    let contentModificationDate: Date?
    let attributeModificationDate: Date?
    let contentAccessDate: Date?
    let addedToDirectoryDate: Date?

    let logicalSize: Int64?
    let allocatedSize: Int64?

    let ownerAccountName: String?
    let groupOwnerAccountName: String?
    let posixPermissions: Int?
    let isReadable: Bool?
    let isWritable: Bool?
    let isExecutable: Bool?
    let finderTags: [String]

    let isDirectory: Bool
    let isPackage: Bool
    let isSymbolicLink: Bool
    let formatDetails: FileFormatDetails?

    var octalPermissions: String? {
        guard let posixPermissions else {
            return nil
        }

        return String(format: "%04o", posixPermissions & 0o7777)
    }

    var symbolicPermissions: String? {
        guard let posixPermissions else {
            return nil
        }

        let masksAndCharacters: [(Int, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]

        return String(masksAndCharacters.map { mask, character in
            posixPermissions & mask == mask ? character : "-"
        })
    }

    var permissionsDescription: String? {
        guard let symbolicPermissions, let octalPermissions else {
            return nil
        }
        return "\(symbolicPermissions) (\(octalPermissions))"
    }

    func replacingFormatDetails(_ formatDetails: FileFormatDetails?) -> FilePreviewMetadata {
        FilePreviewMetadata(
            url: url,
            revision: revision,
            name: name,
            kindDescription: kindDescription,
            fileExtension: fileExtension,
            typeIdentifier: typeIdentifier,
            mimeType: mimeType,
            fullPath: fullPath,
            parentPath: parentPath,
            volumeName: volumeName,
            volumeKind: volumeKind,
            symbolicLinkTarget: symbolicLinkTarget,
            creationDate: creationDate,
            contentModificationDate: contentModificationDate,
            attributeModificationDate: attributeModificationDate,
            contentAccessDate: contentAccessDate,
            addedToDirectoryDate: addedToDirectoryDate,
            logicalSize: logicalSize,
            allocatedSize: allocatedSize,
            ownerAccountName: ownerAccountName,
            groupOwnerAccountName: groupOwnerAccountName,
            posixPermissions: posixPermissions,
            isReadable: isReadable,
            isWritable: isWritable,
            isExecutable: isExecutable,
            finderTags: finderTags,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isSymbolicLink: isSymbolicLink,
            formatDetails: formatDetails
        )
    }
}
