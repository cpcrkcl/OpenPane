//
//  FileOperationService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation

enum FileOperationError: LocalizedError, Equatable, Sendable {
    case emptyName
    case destinationIsNotDirectory(URL)
    case destinationExists(URL)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Name cannot be empty."
        case .destinationIsNotDirectory(let url):
            return "\(url.path) is not a folder."
        case .destinationExists(let url):
            return "An item named \(url.lastPathComponent) already exists."
        }
    }
}

nonisolated protocol FileOperationServicing: Sendable {
    nonisolated func copy(items: [FileItem], to destinationDirectory: URL) async throws
    nonisolated func move(items: [FileItem], to destinationDirectory: URL) async throws
    nonisolated func rename(item: FileItem, to newName: String) async throws -> URL
    nonisolated func createFolder(named name: String, in directory: URL) async throws -> URL
}

nonisolated struct FileOperationService: FileOperationServicing {
    nonisolated func copy(items: [FileItem], to destinationDirectory: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.validateDirectory(destinationDirectory)

            for item in items {
                let destinationURL = destinationDirectory.appendingPathComponent(item.name, isDirectory: item.isDirectory)
                try Self.validateDestinationDoesNotExist(destinationURL)
                try FileManager.default.copyItem(at: item.url, to: destinationURL)
            }
        }.value
    }

    nonisolated func move(items: [FileItem], to destinationDirectory: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.validateDirectory(destinationDirectory)

            for item in items {
                let destinationURL = destinationDirectory.appendingPathComponent(item.name, isDirectory: item.isDirectory)
                try Self.validateDestinationDoesNotExist(destinationURL)
                try FileManager.default.moveItem(at: item.url, to: destinationURL)
            }
        }.value
    }

    nonisolated func rename(item: FileItem, to newName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let trimmedName = try Self.validateName(newName)
            let destinationURL = item.url
                .deletingLastPathComponent()
                .appendingPathComponent(trimmedName, isDirectory: item.isDirectory)

            try Self.validateDestinationDoesNotExist(destinationURL)
            try FileManager.default.moveItem(at: item.url, to: destinationURL)

            return destinationURL
        }.value
    }

    nonisolated func createFolder(named name: String, in directory: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let trimmedName = try Self.validateName(name)
            try Self.validateDirectory(directory)

            let folderURL = directory.appendingPathComponent(trimmedName, isDirectory: true)
            try Self.validateDestinationDoesNotExist(folderURL)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)

            return folderURL
        }.value
    }

    private nonisolated static func validateName(_ name: String) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw FileOperationError.emptyName
        }

        return trimmedName
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
}
