//
//  FileOperationService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation

enum FileConflictResolution: Equatable, Sendable {
    case cancel
    case skip
    case replace
    case keepBoth
}

enum FileOperationError: LocalizedError, Equatable, Sendable {
    case emptyName
    case invalidName(String)
    case sourceDoesNotExist(URL)
    case destinationIsNotDirectory(URL)
    case destinationExists(URL)
    case operationCancelled(URL)
    case cannotReplaceItemWithItself(URL)
    case duplicateDestinationNames
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
        case .operationCancelled(let url):
            return "Operation cancelled because an item named \(Self.displayName(for: url)) already exists."
        case .cannotReplaceItemWithItself(let url):
            return "Cannot replace \(Self.displayName(for: url)) with itself."
        case .duplicateDestinationNames:
            return "The rename pattern creates duplicate names."
        case .operationFailed(let action, let url, let reason):
            return "Could not \(action) \(Self.displayName(for: url)): \(reason)"
        case .trashFailed(let url, let reason):
            return "Could not move \(Self.displayName(for: url)) to Trash: \(reason)"
        }
    }

    private static func displayName(for url: URL) -> String {
        url.openPaneDisplayName
    }
}

nonisolated protocol FileOperationServicing: Sendable {
    nonisolated func copy(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution
    ) async throws

    nonisolated func move(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution
    ) async throws

    nonisolated func trash(items: [FileItem]) async throws
    nonisolated func rename(item: FileItem, to newName: String) async throws -> URL
    nonisolated func batchRename(
        items: [FileItem],
        baseName: String,
        startingNumber: Int,
        preserveExtensions: Bool
    ) async throws -> [URL]
    nonisolated func createFolder(named name: String, in directory: URL) async throws -> URL
    nonisolated func createFile(named name: String, in directory: URL) async throws -> URL
}

extension FileOperationServicing {
    nonisolated func copy(items: [FileItem], to destinationDirectory: URL) async throws {
        try await copy(items: items, to: destinationDirectory, conflictResolution: .cancel)
    }

    nonisolated func move(items: [FileItem], to destinationDirectory: URL) async throws {
        try await move(items: items, to: destinationDirectory, conflictResolution: .cancel)
    }
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

    private struct TransferPlan: Sendable {
        let item: FileItem
        let destinationURL: URL
        let shouldReplaceExistingItem: Bool
    }

    private struct RenamePlan: Sendable {
        let item: FileItem
        let destinationURL: URL
    }

    nonisolated init(trashService: any TrashServicing = FileManagerTrashService()) {
        self.trashService = trashService
    }

    nonisolated func copy(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution
    ) async throws {
        let trashService = trashService

        try await Task.detached(priority: .userInitiated) {
            let plans = try Self.transferPlans(
                for: items,
                to: destinationDirectory,
                conflictResolution: conflictResolution
            )

            for plan in plans {
                if plan.shouldReplaceExistingItem {
                    do {
                        try trashService.trashItem(at: plan.destinationURL)
                    } catch {
                        throw FileOperationError.trashFailed(plan.destinationURL, Self.userReadableReason(for: error))
                    }
                }

                do {
                    try FileManager.default.copyItem(at: plan.item.url, to: plan.destinationURL)
                } catch {
                    throw FileOperationError.operationFailed("copy", plan.item.url, Self.userReadableReason(for: error))
                }
            }
        }.value
    }

    nonisolated func move(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution
    ) async throws {
        let trashService = trashService

        try await Task.detached(priority: .userInitiated) {
            let plans = try Self.transferPlans(
                for: items,
                to: destinationDirectory,
                conflictResolution: conflictResolution
            )

            for plan in plans {
                if plan.shouldReplaceExistingItem {
                    do {
                        try trashService.trashItem(at: plan.destinationURL)
                    } catch {
                        throw FileOperationError.trashFailed(plan.destinationURL, Self.userReadableReason(for: error))
                    }
                }

                do {
                    try FileManager.default.moveItem(at: plan.item.url, to: plan.destinationURL)
                } catch {
                    throw FileOperationError.operationFailed("move", plan.item.url, Self.userReadableReason(for: error))
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

    nonisolated func batchRename(
        items: [FileItem],
        baseName: String,
        startingNumber: Int,
        preserveExtensions: Bool = true
    ) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            let plans = try Self.batchRenamePlans(
                for: items,
                baseName: baseName,
                startingNumber: startingNumber,
                preserveExtensions: preserveExtensions
            )

            for plan in plans {
                do {
                    try FileManager.default.moveItem(at: plan.item.url, to: plan.destinationURL)
                } catch {
                    throw FileOperationError.operationFailed("rename", plan.item.url, Self.userReadableReason(for: error))
                }
            }

            return plans.map(\.destinationURL)
        }.value
    }

    nonisolated static func batchRenamePreviewNames(
        for items: [FileItem],
        baseName: String,
        startingNumber: Int,
        preserveExtensions: Bool = true
    ) throws -> [String] {
        let trimmedBaseName = try validateName(baseName)

        return sortedForBatchRename(items).enumerated().map { index, item in
            batchRenameName(
                for: item,
                baseName: trimmedBaseName,
                number: startingNumber + index,
                preserveExtension: preserveExtensions
            )
        }
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

    nonisolated func createFile(named name: String, in directory: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let trimmedName = try Self.validateName(name)
            try Self.validateDirectory(directory)

            let fileURL = directory.appendingPathComponent(trimmedName, isDirectory: false)
            try Self.validateDestinationDoesNotExist(fileURL)

            guard FileManager.default.createFile(atPath: fileURL.path, contents: Data()) else {
                throw FileOperationError.operationFailed("create file", fileURL, "The operation could not be completed.")
            }

            return fileURL
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

        guard trimmedName != "." && trimmedName != ".." else {
            throw FileOperationError.invalidName(trimmedName)
        }

        return trimmedName
    }

    private nonisolated static func transferPlans(
        for items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution
    ) throws -> [TransferPlan] {
        try validateDirectory(destinationDirectory)
        var destinationURLs: Set<URL> = []

        return try items.compactMap { item in
            try validateSourceExists(item.url)
            let destinationURL = destinationDirectory.appendingPathComponent(item.name, isDirectory: item.isDirectory)
            let destinationIsReserved = destinationURLs.contains(destinationURL)
            let destinationExists = FileManager.default.fileExists(atPath: destinationURL.path)

            guard destinationExists || destinationIsReserved else {
                destinationURLs.insert(destinationURL)
                return TransferPlan(item: item, destinationURL: destinationURL, shouldReplaceExistingItem: false)
            }

            switch conflictResolution {
            case .cancel:
                throw FileOperationError.operationCancelled(destinationURL)
            case .skip:
                return nil
            case .replace:
                guard !destinationIsReserved else {
                    throw FileOperationError.destinationExists(destinationURL)
                }

                guard item.url.standardizedFileURL != destinationURL.standardizedFileURL else {
                    throw FileOperationError.cannotReplaceItemWithItself(destinationURL)
                }

                destinationURLs.insert(destinationURL)
                return TransferPlan(item: item, destinationURL: destinationURL, shouldReplaceExistingItem: true)
            case .keepBoth:
                let uniqueDestinationURL = uniqueCopyURL(for: destinationURL, reservedURLs: destinationURLs)
                destinationURLs.insert(uniqueDestinationURL)
                return TransferPlan(item: item, destinationURL: uniqueDestinationURL, shouldReplaceExistingItem: false)
            }
        }
    }

    private nonisolated static func batchRenamePlans(
        for items: [FileItem],
        baseName: String,
        startingNumber: Int,
        preserveExtensions: Bool
    ) throws -> [RenamePlan] {
        let previewNames = try batchRenamePreviewNames(
            for: items,
            baseName: baseName,
            startingNumber: startingNumber,
            preserveExtensions: preserveExtensions
        )
        var destinationURLs: Set<URL> = []
        var sourceURLs = Set(items.map { $0.url.standardizedFileURL })
        let sortedItems = sortedForBatchRename(items)

        guard Set(previewNames).count == previewNames.count else {
            throw FileOperationError.duplicateDestinationNames
        }

        return try zip(sortedItems, previewNames).map { item, newName in
            _ = try validateName(newName)
            try validateSourceExists(item.url)

            let destinationURL = item.url
                .deletingLastPathComponent()
                .appendingPathComponent(newName, isDirectory: item.isDirectory)
            let standardizedDestinationURL = destinationURL.standardizedFileURL

            guard destinationURLs.insert(standardizedDestinationURL).inserted else {
                throw FileOperationError.duplicateDestinationNames
            }

            if standardizedDestinationURL != item.url.standardizedFileURL,
               FileManager.default.fileExists(atPath: destinationURL.path),
               !sourceURLs.contains(standardizedDestinationURL) {
                throw FileOperationError.destinationExists(destinationURL)
            }

            sourceURLs.remove(item.url.standardizedFileURL)
            return RenamePlan(item: item, destinationURL: destinationURL)
        }
    }

    private nonisolated static func sortedForBatchRename(_ items: [FileItem]) -> [FileItem] {
        items.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private nonisolated static func batchRenameName(
        for item: FileItem,
        baseName: String,
        number: Int,
        preserveExtension: Bool
    ) -> String {
        let numberedBaseName = "\(baseName) \(number)"

        guard preserveExtension,
              !item.isDirectory,
              !item.url.pathExtension.isEmpty else {
            return numberedBaseName
        }

        return "\(numberedBaseName).\(item.url.pathExtension)"
    }

    private nonisolated static func uniqueCopyURL(for url: URL, reservedURLs: Set<URL>) -> URL {
        let directoryURL = url.deletingLastPathComponent()
        let pathExtension = url.pathExtension
        let baseName = pathExtension.isEmpty
            ? url.lastPathComponent
            : url.deletingPathExtension().lastPathComponent

        var copyNumber = 1

        while true {
            let copySuffix = copyNumber == 1 ? " copy" : " copy \(copyNumber)"
            let candidateName = "\(baseName)\(copySuffix)"
            let candidateURL = pathExtension.isEmpty
                ? directoryURL.appendingPathComponent(candidateName)
                : directoryURL.appendingPathComponent(candidateName).appendingPathExtension(pathExtension)

            if !reservedURLs.contains(candidateURL),
               !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }

            copyNumber += 1
        }
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

        if nsError.localizedDescription != "The operation couldn’t be completed." {
            return nsError.localizedDescription
        }

        return "The operation could not be completed."
    }
}
