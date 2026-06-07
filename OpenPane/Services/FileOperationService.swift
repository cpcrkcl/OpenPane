//
//  FileOperationService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation

enum FileOperationError: LocalizedError, Equatable, Sendable {
    case emptyName
    case invalidName(String)
    case sourceDoesNotExist(URL)
    case destinationIsNotDirectory(URL)
    case destinationExists(URL)
    case operationFailed(String, URL, String)
    case trashFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Name cannot be empty."
        case .invalidName(let name):
            return "\(name) is not a valid name."
        case .sourceDoesNotExist(let url):
            return "\(Self.displayName(for: url)) could not be found."
        case .destinationIsNotDirectory(let url):
            return "\(Self.displayName(for: url)) is not a folder."
        case .destinationExists(let url):
            return "An item named \(Self.displayName(for: url)) already exists."
        case .operationFailed(let action, let url, let reason):
            return "Could not \(action) \(Self.displayName(for: url)): \(reason)"
        case .trashFailed(let url, let reason):
            return "Could not move \(Self.displayName(for: url)) to Trash: \(reason)"
        }
    }

    private static func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}

nonisolated protocol FileOperationServicing: Sendable {
    nonisolated func copy(items: [FileItem], to destinationDirectory: URL) async throws
    nonisolated func move(items: [FileItem], to destinationDirectory: URL) async throws
    nonisolated func trash(items: [FileItem]) async throws
    nonisolated func rename(item: FileItem, to newName: String) async throws -> URL
    nonisolated func createFolder(named name: String, in directory: URL) async throws -> URL
}

nonisolated protocol TrashServicing: Sendable {
    nonisolated func trashItem(at url: URL) throws
}

nonisolated struct FileManagerTrashService: TrashServicing {
    nonisolated func trashItem(at url: URL) throws {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
    }
}

nonisolated struct FileOperationService: FileOperationServicing {
    private let trashService: any TrashServicing

    nonisolated init(trashService: any TrashServicing = FileManagerTrashService()) {
        self.trashService = trashService
    }

    nonisolated func copy(items: [FileItem], to destinationDirectory: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.validateDirectory(destinationDirectory)

            for item in items {
                try Self.validateSourceExists(item.url)
                let destinationURL = destinationDirectory.appendingPathComponent(item.name, isDirectory: item.isDirectory)
                try Self.validateDestinationDoesNotExist(destinationURL)

                do {
                    try FileManager.default.copyItem(at: item.url, to: destinationURL)
                } catch {
                    throw FileOperationError.operationFailed("copy", item.url, Self.userReadableReason(for: error))
                }
            }
        }.value
    }

    nonisolated func move(items: [FileItem], to destinationDirectory: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.validateDirectory(destinationDirectory)

            for item in items {
                try Self.validateSourceExists(item.url)
                let destinationURL = destinationDirectory.appendingPathComponent(item.name, isDirectory: item.isDirectory)
                try Self.validateDestinationDoesNotExist(destinationURL)

                do {
                    try FileManager.default.moveItem(at: item.url, to: destinationURL)
                } catch {
                    throw FileOperationError.operationFailed("move", item.url, Self.userReadableReason(for: error))
                }
            }
        }.value
    }

    nonisolated func trash(items: [FileItem]) async throws {
        let trashService = trashService

        try await Task.detached(priority: .userInitiated) {
            for item in items {
                do {
                    try trashService.trashItem(at: item.url)
                } catch {
                    throw FileOperationError.trashFailed(item.url, Self.userReadableReason(for: error))
                }
            }
        }.value
    }

    nonisolated func rename(item: FileItem, to newName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let trimmedName = try Self.validateName(newName)
            try Self.validateSourceExists(item.url)

            let destinationURL = item.url
                .deletingLastPathComponent()
                .appendingPathComponent(trimmedName, isDirectory: item.isDirectory)

            try Self.validateDestinationDoesNotExist(destinationURL)

            do {
                try FileManager.default.moveItem(at: item.url, to: destinationURL)
            } catch {
                throw FileOperationError.operationFailed("rename", item.url, Self.userReadableReason(for: error))
            }

            return destinationURL
        }.value
    }

    nonisolated func createFolder(named name: String, in directory: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let trimmedName = try Self.validateName(name)
            try Self.validateDirectory(directory)

            let folderURL = directory.appendingPathComponent(trimmedName, isDirectory: true)
            try Self.validateDestinationDoesNotExist(folderURL)

            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            } catch {
                throw FileOperationError.operationFailed("create folder", folderURL, Self.userReadableReason(for: error))
            }

            return folderURL
        }.value
    }

    private nonisolated static func validateName(_ name: String) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw FileOperationError.emptyName
        }

        guard trimmedName.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil else {
            throw FileOperationError.invalidName(trimmedName)
        }

        return trimmedName
    }

    private nonisolated static func validateSourceExists(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileOperationError.sourceDoesNotExist(url)
        }
    }

    private nonisolated static func validateDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileOperationError.destinationIsNotDirectory(url)
        }
    }

    private nonisolated static func validateDestinationDoesNotExist(_ url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw FileOperationError.destinationExists(url)
        }
    }

    private nonisolated static func userReadableReason(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteNoPermissionError {
            return "Permission denied."
        }

        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
            return "The item could not be found."
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return "The operation could not be completed."
    }
}
