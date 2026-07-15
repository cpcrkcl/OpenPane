//
//  FileOperationService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Darwin
import Foundation

enum FileConflictResolution: Equatable, Sendable {
    case cancel
    case skip
    case replace
    case keepBoth
}

nonisolated struct FileOperationProgress: Equatable, Sendable {
    let completedItemCount: Int
    let totalItemCount: Int
    let currentItemName: String?
    let completedByteCount: Int64?
    let totalByteCount: Int64?

    init(
        completedItemCount: Int,
        totalItemCount: Int,
        currentItemName: String? = nil,
        completedByteCount: Int64? = nil,
        totalByteCount: Int64? = nil
    ) {
        let sanitizedTotal = max(0, totalItemCount)
        self.totalItemCount = sanitizedTotal
        self.completedItemCount = min(max(0, completedItemCount), sanitizedTotal)
        self.currentItemName = currentItemName

        if let totalByteCount, totalByteCount > 0 {
            self.totalByteCount = totalByteCount
            self.completedByteCount = min(max(0, completedByteCount ?? 0), totalByteCount)
        } else {
            self.totalByteCount = nil
            self.completedByteCount = nil
        }
    }
}

typealias FileOperationProgressHandler = @Sendable (FileOperationProgress) -> Void

enum FileOperationError: LocalizedError, Equatable, Sendable {
    case noItems
    case emptyName
    case invalidName(String)
    case sourceDoesNotExist(URL)
    case destinationIsNotDirectory(URL)
    case destinationIsNotWritable(URL)
    case destinationExists(URL)
    case operationCancelled(URL)
    case cannotReplaceItemWithItself(URL)
    case cannotPlaceFolderInsideItself(URL)
    case duplicateDestinationNames
    case operationFailed(String, URL, String)
    case trashFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .noItems:
            return "Select one or more items."
        case .emptyName:
            return "Name cannot be empty."
        case .invalidName(let name):
            return "\(name) is not a valid name."
        case .sourceDoesNotExist(let url):
            return "\(Self.displayName(for: url)) could not be found."
        case .destinationIsNotDirectory(let url):
            return "\(Self.displayName(for: url)) is not a folder."
        case .destinationIsNotWritable(let url):
            return "You do not have permission to write to \(Self.displayName(for: url))."
        case .destinationExists(let url):
            return "An item named \(Self.displayName(for: url)) already exists."
        case .operationCancelled(let url):
            return "Operation cancelled because an item named \(Self.displayName(for: url)) already exists."
        case .cannotReplaceItemWithItself(let url):
            return "Cannot replace \(Self.displayName(for: url)) with itself."
        case .cannotPlaceFolderInsideItself(let url):
            return "Cannot place \(Self.displayName(for: url)) inside itself."
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
        conflictResolution: FileConflictResolution,
        progressHandler: FileOperationProgressHandler?
    ) async throws

    nonisolated func move(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution,
        progressHandler: FileOperationProgressHandler?
    ) async throws

    nonisolated func trash(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws
    nonisolated func duplicate(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws
    nonisolated func compress(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws -> URL
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
    nonisolated func copy(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution
    ) async throws {
        try await copy(
            items: items,
            to: destinationDirectory,
            conflictResolution: conflictResolution,
            progressHandler: nil
        )
    }

    nonisolated func copy(items: [FileItem], to destinationDirectory: URL) async throws {
        try await copy(
            items: items,
            to: destinationDirectory,
            conflictResolution: .cancel,
            progressHandler: nil
        )
    }

    nonisolated func move(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution
    ) async throws {
        try await move(
            items: items,
            to: destinationDirectory,
            conflictResolution: conflictResolution,
            progressHandler: nil
        )
    }

    nonisolated func move(items: [FileItem], to destinationDirectory: URL) async throws {
        try await move(
            items: items,
            to: destinationDirectory,
            conflictResolution: .cancel,
            progressHandler: nil
        )
    }

    nonisolated func trash(items: [FileItem]) async throws {
        try await trash(items: items, progressHandler: nil)
    }

    nonisolated func duplicate(items: [FileItem]) async throws {
        try await duplicate(items: items, progressHandler: nil)
    }

    nonisolated func compress(items: [FileItem]) async throws -> URL {
        try await compress(items: items, progressHandler: nil)
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

nonisolated protocol FileSystemOperating: Sendable {
    nonisolated func copyItem(at sourceURL: URL, to destinationURL: URL) throws
    nonisolated func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    nonisolated func moveItemExclusively(at sourceURL: URL, to destinationURL: URL) throws
    nonisolated func removeItem(at url: URL) throws
    nonisolated func replaceItem(at originalURL: URL, withItemAt replacementURL: URL) throws
    nonisolated func fileExists(at url: URL) -> Bool
    nonisolated func fileExists(at url: URL, isDirectory: inout ObjCBool) -> Bool
    nonisolated func isWritableFile(at url: URL) -> Bool
    nonisolated func contentsOfDirectory(at url: URL) throws -> [URL]
    nonisolated func createDirectory(at url: URL) throws
    nonisolated func createFile(at url: URL) -> Bool
}

nonisolated struct FileManagerFileSystem: FileSystemOperating {
    nonisolated func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    nonisolated func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    nonisolated func moveItemExclusively(at sourceURL: URL, to destinationURL: URL) throws {
        let result = sourceURL.withUnsafeFileSystemRepresentation { sourcePath -> Int32 in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL))
            }
        }

        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    nonisolated func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    nonisolated func replaceItem(at originalURL: URL, withItemAt replacementURL: URL) throws {
        _ = try FileManager.default.replaceItemAt(
            originalURL,
            withItemAt: replacementURL,
            backupItemName: nil,
            options: []
        )
    }

    nonisolated func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    nonisolated func fileExists(at url: URL, isDirectory: inout ObjCBool) -> Bool {
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    }

    nonisolated func isWritableFile(at url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    nonisolated func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
    }

    nonisolated func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    nonisolated func createFile(at url: URL) -> Bool {
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }
}

/// The native, metadata-preserving path used for byte-copy operations. It is
/// intentionally separate from `FileSystemOperating` so existing move and
/// rename operations stay small and testable without invoking Darwin APIs.
nonisolated protocol FileTransferServicing: Sendable {
    nonisolated func copyItem(
        at sourceURL: URL,
        to destinationURL: URL,
        progressHandler: @escaping @Sendable (Int64) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws
}

nonisolated protocol VolumeIdentityProviding: Sendable {
    nonisolated func isSameVolume(sourceURL: URL, destinationDirectoryURL: URL) -> Bool
}

nonisolated struct ResourceVolumeIdentityProvider: VolumeIdentityProviding {
    nonisolated func isSameVolume(sourceURL: URL, destinationDirectoryURL: URL) -> Bool {
        guard let sourceVolume = try? sourceURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject,
              let destinationVolume = try? destinationDirectoryURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject else {
            // An unknown volume is treated as cross-volume so we preserve the
            // source until the destination has been safely published.
            return false
        }

        return sourceVolume.isEqual(destinationVolume)
    }
}

nonisolated struct CopyfileTransferService: FileTransferServicing {
    nonisolated func copyItem(
        at sourceURL: URL,
        to destinationURL: URL,
        progressHandler: @escaping @Sendable (Int64) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws {
        let context = CopyfileTransferCallbackContext(
            progressHandler: progressHandler,
            isCancelled: isCancelled
        )
        guard let state = copyfile_state_alloc() else {
            throw POSIXError(.ENOMEM)
        }
        defer { copyfile_state_free(state) }

        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        guard copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), contextPointer) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let callbackPointer = unsafeBitCast(
            openPaneCopyfileProgressCallback,
            to: UnsafeRawPointer.self
        )
        guard copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), callbackPointer) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let result = sourceURL.withUnsafeFileSystemRepresentation { sourcePath in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                copyfile(
                    sourcePath,
                    destinationPath,
                    state,
                    copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC)
                )
            }
        }

        guard result == 0 else {
            if isCancelled() {
                throw CancellationError()
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        if isCancelled() {
            throw CancellationError()
        }

        context.finish()
    }
}

nonisolated private final class CopyfileTransferCallbackContext: @unchecked Sendable {
    private let lock = NSLock()
    private let progressHandler: @Sendable (Int64) -> Void
    private let isCancelled: @Sendable () -> Bool
    private var completedFileBytes: Int64 = 0
    private var currentFileBytes: Int64 = 0

    init(
        progressHandler: @escaping @Sendable (Int64) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) {
        self.progressHandler = progressHandler
        self.isCancelled = isCancelled
    }

    func shouldCancel() -> Bool {
        isCancelled()
    }

    func report(copiedByteCount: Int64) {
        let progress = lock.withLock {
            currentFileBytes = max(currentFileBytes, max(0, copiedByteCount))
            return completedFileBytes + currentFileBytes
        }
        progressHandler(progress)
    }

    func finishCurrentFile() {
        let progress = lock.withLock { () -> Int64 in
            completedFileBytes += currentFileBytes
            currentFileBytes = 0
            return completedFileBytes
        }
        progressHandler(progress)
    }

    func finish() {
        let progress = lock.withLock { () -> Int64 in
            completedFileBytes += currentFileBytes
            currentFileBytes = 0
            return completedFileBytes
        }
        progressHandler(progress)
    }
}

nonisolated(unsafe) private let openPaneCopyfileProgressCallback: @convention(c) (
    Int32,
    Int32,
    copyfile_state_t?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafeMutableRawPointer?
) -> Int32 = { what, stage, state, source, destination, contextPointer in
    _ = stage
    _ = source
    _ = destination

    guard let contextPointer else {
        return Int32(COPYFILE_QUIT)
    }

    let context = Unmanaged<CopyfileTransferCallbackContext>
        .fromOpaque(contextPointer)
        .takeUnretainedValue()
    guard !context.shouldCancel() else {
        return Int32(COPYFILE_QUIT)
    }

    if what == Int32(COPYFILE_COPY_DATA), stage == Int32(COPYFILE_PROGRESS) {
        var copiedByteCount: off_t = 0
        if let state,
           copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copiedByteCount) == 0 {
            context.report(copiedByteCount: Int64(copiedByteCount))
        }
    }

    if what == Int32(COPYFILE_RECURSE_FILE), stage == Int32(COPYFILE_FINISH) {
        context.finishCurrentFile()
    }

    return Int32(COPYFILE_CONTINUE)
}

nonisolated protocol ArchiveProcessRunning: Sendable {
    nonisolated func createArchive(from items: [FileItem], at archiveURL: URL) async throws
}

nonisolated struct DittoArchiveProcessRunner: ArchiveProcessRunning {
    private final class CancellableProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?

        func setProcess(_ process: Process) {
            lock.lock()
            self.process = process
            lock.unlock()
        }

        func clearProcess(_ process: Process) {
            lock.lock()
            if self.process === process {
                self.process = nil
            }
            lock.unlock()
        }

        func terminateProcess() {
            lock.lock()
            let process = process
            lock.unlock()

            if process?.isRunning == true {
                process?.terminate()
            }
        }
    }

    nonisolated func createArchive(from items: [FileItem], at archiveURL: URL) async throws {
        guard let firstItem = items.first else {
            throw FileOperationError.noItems
        }

        let processBox = CancellableProcessBox()
        let operationIdentifier = UUID().uuidString

        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            var stagingDirectoryURL: URL?
            defer {
                if let stagingDirectoryURL {
                    try? FileManager.default.removeItem(at: stagingDirectoryURL)
                }
            }

            let archiveSourceURL: URL
            let keepsSourceParent: Bool

            if items.count == 1 {
                archiveSourceURL = firstItem.url
                keepsSourceParent = true
            } else {
                let stagingURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "OpenPane-Archive-\(operationIdentifier)",
                        isDirectory: true
                    )

                do {
                    try FileManager.default.createDirectory(
                        at: stagingURL,
                        withIntermediateDirectories: false
                    )
                } catch {
                    throw FileOperationError.operationFailed(
                        "compress",
                        archiveURL,
                        Self.userReadableReason(for: error)
                    )
                }

                stagingDirectoryURL = stagingURL

                for item in items {
                    try Task.checkCancellation()
                    let stagedItemURL = stagingURL.appendingPathComponent(
                        item.url.lastPathComponent,
                        isDirectory: item.isDirectory
                    )

                    do {
                        try FileManager.default.copyItem(at: item.url, to: stagedItemURL)
                    } catch {
                        throw FileOperationError.operationFailed(
                            "compress",
                            archiveURL,
                            Self.userReadableReason(for: error)
                        )
                    }
                }

                archiveSourceURL = stagingURL
                keepsSourceParent = false
            }

            try Task.checkCancellation()
            var arguments = [
                "-c",
                "-k",
                "--sequesterRsrc"
            ]
            if keepsSourceParent {
                arguments.append("--keepParent")
            }
            arguments.append(contentsOf: [archiveSourceURL.path, archiveURL.path])

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = arguments

            let errorPipe = Pipe()
            process.standardError = errorPipe
            processBox.setProcess(process)
            defer {
                processBox.clearProcess(process)
            }

            do {
                try process.run()
            } catch {
                throw FileOperationError.operationFailed("compress", archiveURL, Self.userReadableReason(for: error))
            }

            while process.isRunning {
                do {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch is CancellationError {
                    processBox.terminateProcess()
                    throw CancellationError()
                }
            }

            try Task.checkCancellation()
            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw FileOperationError.operationFailed(
                    "compress",
                    archiveURL,
                    errorMessage?.isEmpty == false ? errorMessage! : "The archive could not be created."
                )
            }

        } onCancel: {
            processBox.terminateProcess()
        }
    }

    private nonisolated static func userReadableReason(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.localizedDescription != "The operation couldn’t be completed." {
            return nsError.localizedDescription
        }

        return "The operation could not be completed."
    }
}

nonisolated private final class FileOperationProgressCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private let handler: FileOperationProgressHandler
    private var lastEmission = Date.distantPast

    init(handler: @escaping FileOperationProgressHandler) {
        self.handler = handler
    }

    func report(_ progress: FileOperationProgress, force: Bool = false) {
        let shouldEmit = lock.withLock { () -> Bool in
            let now = Date()
            guard force || now.timeIntervalSince(lastEmission) >= 0.1 else {
                return false
            }
            lastEmission = now
            return true
        }

        guard shouldEmit else {
            return
        }
        handler(progress)
    }
}

nonisolated struct FileOperationService: FileOperationServicing {
    private let trashService: any TrashServicing
    private let fileSystem: any FileSystemOperating
    private let archiveProcessRunner: any ArchiveProcessRunning
    private let fileTransferService: (any FileTransferServicing)?
    private let volumeIdentityProvider: any VolumeIdentityProviding

    private struct TransferPlan: Sendable {
        let item: FileItem
        let destinationURL: URL
        let shouldReplaceExistingItem: Bool
    }

    private struct RenamePlan: Sendable {
        let item: FileItem
        let destinationURL: URL
    }

    private struct StagedRenamePlan: Sendable {
        let plan: RenamePlan
        let temporaryURL: URL
    }

    private struct ArchiveDestination: Sendable {
        let directoryURL: URL
        let baseName: String
    }

    private struct SourceCleanupFailure: LocalizedError, Sendable {
        let reason: String

        var errorDescription: String? {
            "Destination was replaced, but the original item could not be removed: \(reason)"
        }
    }

    private struct DestinationIdentity: Hashable, Sendable {
        let parentIdentity: String
        let nameKey: String
    }

    nonisolated init(
        trashService: any TrashServicing = FileManagerTrashService(),
        fileSystem: any FileSystemOperating = FileManagerFileSystem(),
        archiveProcessRunner: any ArchiveProcessRunning = DittoArchiveProcessRunner(),
        fileTransferService: (any FileTransferServicing)? = nil,
        volumeIdentityProvider: any VolumeIdentityProviding = ResourceVolumeIdentityProvider()
    ) {
        self.trashService = trashService
        self.fileSystem = fileSystem
        self.archiveProcessRunner = archiveProcessRunner
        self.fileTransferService = fileTransferService ??
            (fileSystem is FileManagerFileSystem ? CopyfileTransferService() : nil)
        self.volumeIdentityProvider = volumeIdentityProvider
    }

    private nonisolated static func runUserInitiated<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try operation()
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func reportProgress(
        completedItemCount: Int,
        totalItemCount: Int,
        currentItemName: String? = nil,
        completedByteCount: Int64? = nil,
        totalByteCount: Int64? = nil,
        to progressHandler: FileOperationProgressHandler?
    ) {
        progressHandler?(
            FileOperationProgress(
                completedItemCount: completedItemCount,
                totalItemCount: totalItemCount,
                currentItemName: currentItemName,
                completedByteCount: completedByteCount,
                totalByteCount: totalByteCount
            )
        )
    }

    private nonisolated static func transferableByteCounts(for plans: [TransferPlan]) throws -> [Int64] {
        try plans.map { plan in
            try Task.checkCancellation()
            return try transferableByteCount(at: plan.item.url)
        }
    }

    private nonisolated static func transferableByteCount(at rootURL: URL) throws -> Int64 {
        let rootValues = try rootURL.resourceValues(
            forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        )

        if rootValues.isSymbolicLink != true, rootValues.isRegularFile == true {
            return Int64(rootValues.fileSize ?? 0)
        }

        guard rootValues.isDirectory == true else {
            return 0
        }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            throw FileOperationError.operationFailed("copy", rootURL, "The folder could not be read.")
        }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true, values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }

        return total
    }

    private nonisolated static func copyViaStaging(
        plan: TransferPlan,
        fileSystem: any FileSystemOperating,
        fileTransferService: any FileTransferServicing,
        progressHandler: @escaping @Sendable (Int64) -> Void
    ) throws {
        let stagingURL = plan.shouldReplaceExistingItem
            ? uniqueReplacementStagingURL(
                in: plan.destinationURL.deletingLastPathComponent(),
                isDirectory: plan.item.isDirectory,
                fileSystem: fileSystem
            )
            : uniqueTransferStagingURL(
                in: plan.destinationURL.deletingLastPathComponent(),
                isDirectory: plan.item.isDirectory,
                fileSystem: fileSystem
            )

        do {
            try fileTransferService.copyItem(
                at: plan.item.url,
                to: stagingURL,
                progressHandler: progressHandler,
                isCancelled: { Task.isCancelled }
            )
            try Task.checkCancellation()

            if plan.shouldReplaceExistingItem {
                try fileSystem.replaceItem(at: plan.destinationURL, withItemAt: stagingURL)
            } else {
                try fileSystem.moveItemExclusively(at: stagingURL, to: plan.destinationURL)
            }
        } catch {
            try? fileSystem.removeItem(at: stagingURL)
            throw error
        }
    }

    private nonisolated static func moveAcrossVolumes(
        plan: TransferPlan,
        fileSystem: any FileSystemOperating,
        fileTransferService: any FileTransferServicing,
        progressHandler: @escaping @Sendable (Int64) -> Void
    ) throws {
        try copyViaStaging(
            plan: plan,
            fileSystem: fileSystem,
            fileTransferService: fileTransferService,
            progressHandler: progressHandler
        )

        do {
            try fileSystem.removeItem(at: plan.item.url)
        } catch {
            throw SourceCleanupFailure(reason: Self.userReadableReason(for: error))
        }
    }

    nonisolated func copy(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution,
        progressHandler: FileOperationProgressHandler?
    ) async throws {
        let fileSystem = fileSystem
        let fileTransferService = fileTransferService

        try await Self.runUserInitiated {
            try Task.checkCancellation()
            let plans = try Self.transferPlans(
                for: items,
                to: destinationDirectory,
                conflictResolution: conflictResolution,
                fileSystem: fileSystem
            )
            let byteCounts = try fileTransferService.map { _ in
                try Self.transferableByteCounts(for: plans)
            }
            let totalByteCount = byteCounts?.reduce(0, +) ?? 0
            let usesByteProgress = totalByteCount > 0 && fileTransferService != nil
            let byteProgressCoalescer = progressHandler.map(FileOperationProgressCoalescer.init)
            var completedByteCount: Int64 = 0

            Self.reportProgress(
                completedItemCount: 0,
                totalItemCount: plans.count,
                completedByteCount: usesByteProgress ? 0 : nil,
                totalByteCount: usesByteProgress ? totalByteCount : nil,
                to: progressHandler
            )

            for (index, plan) in plans.enumerated() {
                try Task.checkCancellation()
                Self.reportProgress(
                    completedItemCount: index,
                    totalItemCount: plans.count,
                    currentItemName: plan.item.name,
                    completedByteCount: usesByteProgress ? completedByteCount : nil,
                    totalByteCount: usesByteProgress ? totalByteCount : nil,
                    to: progressHandler
                )

                do {
                    if let fileTransferService {
                        let byteCountBeforeItem = completedByteCount
                        let itemByteCount = byteCounts?[index] ?? 0
                        try Self.copyViaStaging(
                            plan: plan,
                            fileSystem: fileSystem,
                            fileTransferService: fileTransferService,
                            progressHandler: { copiedByteCount in
                                guard usesByteProgress else {
                                    return
                                }
                                byteProgressCoalescer?.report(
                                    FileOperationProgress(
                                        completedItemCount: index,
                                        totalItemCount: plans.count,
                                        currentItemName: plan.item.name,
                                        completedByteCount: byteCountBeforeItem + min(copiedByteCount, itemByteCount),
                                        totalByteCount: totalByteCount
                                    )
                                )
                            }
                        )
                    } else {
                        if plan.shouldReplaceExistingItem {
                            try Self.copyReplacingDestination(plan: plan, fileSystem: fileSystem)
                        } else {
                            try fileSystem.copyItem(at: plan.item.url, to: plan.destinationURL)
                        }
                    }
                    completedByteCount += byteCounts?[index] ?? 0
                    Self.reportProgress(
                        completedItemCount: index + 1,
                        totalItemCount: plans.count,
                        currentItemName: plan.item.name,
                        completedByteCount: usesByteProgress ? completedByteCount : nil,
                        totalByteCount: usesByteProgress ? totalByteCount : nil,
                        to: progressHandler
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw FileOperationError.operationFailed(
                        "copy",
                        plan.item.url,
                        Self.partialFailureReason(
                            for: error,
                            completedCount: index,
                            totalCount: plans.count,
                            completedVerb: "copied"
                        )
                    )
                }
            }
        }
    }

    nonisolated func move(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution,
        progressHandler: FileOperationProgressHandler?
    ) async throws {
        let fileSystem = fileSystem
        let fileTransferService = fileTransferService
        let volumeIdentityProvider = volumeIdentityProvider

        try await Self.runUserInitiated {
            try Task.checkCancellation()
            let plans = try Self.transferPlans(
                for: items,
                to: destinationDirectory,
                conflictResolution: conflictResolution,
                fileSystem: fileSystem
            )
            let requiresByteTransfer = plans.map {
                !volumeIdentityProvider.isSameVolume(
                    sourceURL: $0.item.url,
                    destinationDirectoryURL: destinationDirectory
                )
            }
            let byteCounts = (fileTransferService != nil && requiresByteTransfer.contains(true))
                ? try Self.transferableByteCounts(for: plans)
                : nil
            let totalByteCount = zip(byteCounts ?? [], requiresByteTransfer)
                .reduce(Int64(0)) { partial, entry in
                    partial + (entry.1 ? entry.0 : 0)
                }
            let usesByteProgress = totalByteCount > 0 && fileTransferService != nil
            let byteProgressCoalescer = progressHandler.map(FileOperationProgressCoalescer.init)
            var completedByteCount: Int64 = 0

            Self.reportProgress(
                completedItemCount: 0,
                totalItemCount: plans.count,
                completedByteCount: usesByteProgress ? 0 : nil,
                totalByteCount: usesByteProgress ? totalByteCount : nil,
                to: progressHandler
            )

            for (index, plan) in plans.enumerated() {
                try Task.checkCancellation()
                Self.reportProgress(
                    completedItemCount: index,
                    totalItemCount: plans.count,
                    currentItemName: plan.item.name,
                    completedByteCount: usesByteProgress ? completedByteCount : nil,
                    totalByteCount: usesByteProgress ? totalByteCount : nil,
                    to: progressHandler
                )

                do {
                    if requiresByteTransfer[index], let fileTransferService {
                        let byteCountBeforeItem = completedByteCount
                        let itemByteCount = byteCounts?[index] ?? 0
                        try Self.moveAcrossVolumes(
                            plan: plan,
                            fileSystem: fileSystem,
                            fileTransferService: fileTransferService,
                            progressHandler: { copiedByteCount in
                                guard usesByteProgress else {
                                    return
                                }
                                byteProgressCoalescer?.report(
                                    FileOperationProgress(
                                        completedItemCount: index,
                                        totalItemCount: plans.count,
                                        currentItemName: plan.item.name,
                                        completedByteCount: byteCountBeforeItem + min(copiedByteCount, itemByteCount),
                                        totalByteCount: totalByteCount
                                    )
                                )
                            }
                        )
                        completedByteCount += itemByteCount
                    } else if plan.shouldReplaceExistingItem {
                        try Self.moveReplacingDestination(plan: plan, fileSystem: fileSystem)
                    } else {
                        try fileSystem.moveItem(at: plan.item.url, to: plan.destinationURL)
                    }
                    Self.reportProgress(
                        completedItemCount: index + 1,
                        totalItemCount: plans.count,
                        currentItemName: plan.item.name,
                        completedByteCount: usesByteProgress ? completedByteCount : nil,
                        totalByteCount: usesByteProgress ? totalByteCount : nil,
                        to: progressHandler
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw FileOperationError.operationFailed(
                        "move",
                        plan.item.url,
                        Self.partialFailureReason(
                            for: error,
                            completedCount: index,
                            totalCount: plans.count,
                            completedVerb: "moved"
                        )
                    )
                }
            }
        }
    }

    nonisolated func trash(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws {
        let trashService = trashService

        try await Self.runUserInitiated {
            guard !items.isEmpty else {
                throw FileOperationError.noItems
            }

            Self.reportProgress(completedItemCount: 0, totalItemCount: items.count, to: progressHandler)

            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                Self.reportProgress(
                    completedItemCount: index,
                    totalItemCount: items.count,
                    currentItemName: item.name,
                    to: progressHandler
                )

                do {
                    try trashService.trashItem(at: item.url)
                    Self.reportProgress(
                        completedItemCount: index + 1,
                        totalItemCount: items.count,
                        currentItemName: item.name,
                        to: progressHandler
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw FileOperationError.trashFailed(item.url, Self.userReadableReason(for: error))
                }
            }
        }
    }

    nonisolated func duplicate(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws {
        let fileSystem = fileSystem
        let fileTransferService = fileTransferService

        try await Self.runUserInitiated {
            guard !items.isEmpty else {
                throw FileOperationError.noItems
            }

            var reservedDestinationIdentities: Set<DestinationIdentity> = []
            let plans = try items.map { item in
                try Task.checkCancellation()
                try Self.validateSourceExists(item.url, fileSystem: fileSystem)
                let duplicateURL = Self.uniqueCopyURL(
                    for: item.url,
                    reservedDestinationIdentities: reservedDestinationIdentities,
                    fileSystem: fileSystem
                )
                reservedDestinationIdentities.insert(Self.destinationIdentity(for: duplicateURL))
                return TransferPlan(item: item, destinationURL: duplicateURL, shouldReplaceExistingItem: false)
            }
            let byteCounts = try fileTransferService.map { _ in
                try Self.transferableByteCounts(for: plans)
            }
            let totalByteCount = byteCounts?.reduce(0, +) ?? 0
            let usesByteProgress = totalByteCount > 0 && fileTransferService != nil
            let byteProgressCoalescer = progressHandler.map(FileOperationProgressCoalescer.init)
            var completedByteCount: Int64 = 0

            Self.reportProgress(
                completedItemCount: 0,
                totalItemCount: plans.count,
                completedByteCount: usesByteProgress ? 0 : nil,
                totalByteCount: usesByteProgress ? totalByteCount : nil,
                to: progressHandler
            )

            for (index, plan) in plans.enumerated() {
                try Task.checkCancellation()
                Self.reportProgress(
                    completedItemCount: index,
                    totalItemCount: plans.count,
                    currentItemName: plan.item.name,
                    completedByteCount: usesByteProgress ? completedByteCount : nil,
                    totalByteCount: usesByteProgress ? totalByteCount : nil,
                    to: progressHandler
                )

                do {
                    if let fileTransferService {
                        let byteCountBeforeItem = completedByteCount
                        let itemByteCount = byteCounts?[index] ?? 0
                        try Self.copyViaStaging(
                            plan: plan,
                            fileSystem: fileSystem,
                            fileTransferService: fileTransferService,
                            progressHandler: { copiedByteCount in
                                guard usesByteProgress else {
                                    return
                                }
                                byteProgressCoalescer?.report(
                                    FileOperationProgress(
                                        completedItemCount: index,
                                        totalItemCount: plans.count,
                                        currentItemName: plan.item.name,
                                        completedByteCount: byteCountBeforeItem + min(copiedByteCount, itemByteCount),
                                        totalByteCount: totalByteCount
                                    )
                                )
                            }
                        )
                    } else {
                        try fileSystem.copyItem(at: plan.item.url, to: plan.destinationURL)
                    }
                    completedByteCount += byteCounts?[index] ?? 0
                    Self.reportProgress(
                        completedItemCount: index + 1,
                        totalItemCount: plans.count,
                        currentItemName: plan.item.name,
                        completedByteCount: usesByteProgress ? completedByteCount : nil,
                        totalByteCount: usesByteProgress ? totalByteCount : nil,
                        to: progressHandler
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw FileOperationError.operationFailed(
                        "duplicate",
                        plan.item.url,
                        Self.partialFailureReason(
                            for: error,
                            completedCount: index,
                            totalCount: plans.count,
                            completedVerb: "duplicated"
                        )
                    )
                }
            }
        }
    }

    nonisolated func compress(items: [FileItem], progressHandler: FileOperationProgressHandler?) async throws -> URL {
        let archiveProcessRunner = archiveProcessRunner
        let fileSystem = fileSystem
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let archiveDestination = try Self.archiveDestination(for: items)
            let archiveURL = Self.uniqueArchiveURL(
                in: archiveDestination.directoryURL,
                baseName: archiveDestination.baseName
            )
            let temporaryArchiveDirectoryURL = try Self.createTemporaryArchiveDirectory(
                in: archiveDestination.directoryURL,
                reportingFailureFor: archiveURL,
                fileSystem: fileSystem
            )
            let temporaryArchiveURL = temporaryArchiveDirectoryURL
                .appendingPathComponent("archive.zip", isDirectory: false)
            defer {
                try? fileSystem.removeItem(at: temporaryArchiveURL)
                try? fileSystem.removeItem(at: temporaryArchiveDirectoryURL)
            }

            Self.reportProgress(completedItemCount: 0, totalItemCount: items.count, to: progressHandler)
            Self.reportProgress(
                completedItemCount: 0,
                totalItemCount: items.count,
                currentItemName: items.count == 1 ? items[0].name : "\(items.count) items",
                to: progressHandler
            )

            do {
                try await archiveProcessRunner.createArchive(from: items, at: temporaryArchiveURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw Self.archiveCreationFailure(for: archiveURL, error: error)
            }

            try Task.checkCancellation()
            let publishedArchiveURL = try Self.publishArchive(
                at: temporaryArchiveURL,
                initiallyTo: archiveURL,
                destination: archiveDestination,
                fileSystem: fileSystem
            )
            Self.reportProgress(
                completedItemCount: items.count,
                totalItemCount: items.count,
                currentItemName: publishedArchiveURL.lastPathComponent,
                to: progressHandler
            )
            return publishedArchiveURL
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    nonisolated func rename(item: FileItem, to newName: String) async throws -> URL {
        try await Self.runUserInitiated {
            try Task.checkCancellation()
            let trimmedName = try Self.validateName(newName)
            try Self.validateSourceExists(item.url)

            let destinationURL = item.url
                .deletingLastPathComponent()
                .appendingPathComponent(trimmedName, isDirectory: item.isDirectory)

            guard destinationURL.standardizedFileURL != item.url.standardizedFileURL else {
                return item.url
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                guard Self.urlsReferToSameFile(item.url, destinationURL) else {
                    throw FileOperationError.destinationExists(destinationURL)
                }

                return try Self.renameViaTemporaryURL(item: item, to: destinationURL)
            }

            do {
                try FileManager.default.moveItem(at: item.url, to: destinationURL)
            } catch {
                throw FileOperationError.operationFailed("rename", item.url, Self.userReadableReason(for: error))
            }

            return destinationURL
        }
    }

    nonisolated func batchRename(
        items: [FileItem],
        baseName: String,
        startingNumber: Int,
        preserveExtensions: Bool = true
    ) async throws -> [URL] {
        try await Self.runUserInitiated {
            try Task.checkCancellation()
            let plans = try Self.batchRenamePlans(
                for: items,
                baseName: baseName,
                startingNumber: startingNumber,
                preserveExtensions: preserveExtensions
            )

            try Self.performBatchRename(plans)

            return plans.map(\.destinationURL)
        }
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

    nonisolated static func archiveURL(for items: [FileItem]) throws -> URL {
        let destination = try archiveDestination(for: items)
        return uniqueArchiveURL(in: destination.directoryURL, baseName: destination.baseName)
    }

    private nonisolated static func archiveDestination(for items: [FileItem]) throws -> ArchiveDestination {
        guard let firstItem = items.first else {
            throw FileOperationError.noItems
        }

        try items.forEach { item in
            try Task.checkCancellation()
            try validateSourceExists(item.url)
        }

        let directoryURL = firstItem.url.deletingLastPathComponent()
        let baseName = items.count == 1 ? firstItem.url.lastPathComponent : "Archive"
        return ArchiveDestination(directoryURL: directoryURL, baseName: baseName)
    }

    nonisolated static func validateTransfer(
        items: [FileItem],
        to destinationDirectory: URL,
        conflictResolution: FileConflictResolution = .cancel
    ) throws {
        _ = try transferPlans(
            for: items,
            to: destinationDirectory,
            conflictResolution: conflictResolution,
            fileSystem: FileManagerFileSystem()
        )
    }

    nonisolated static func hasPotentialTransferConflict(
        items: [FileItem],
        to destinationDirectory: URL
    ) -> Bool {
        hasPotentialTransferConflict(
            itemNamesAndDirectoryHints: items.map { ($0.name, $0.isDirectory) },
            to: destinationDirectory,
            fileSystem: FileManagerFileSystem()
        )
    }

    nonisolated static func hasPotentialTransferConflict(
        fileURLs: [URL],
        to destinationDirectory: URL
    ) -> Bool {
        hasPotentialTransferConflict(
            itemNamesAndDirectoryHints: fileURLs.map { ($0.openPaneDisplayName, $0.hasDirectoryPath) },
            to: destinationDirectory,
            fileSystem: FileManagerFileSystem()
        )
    }

    nonisolated func createFolder(named name: String, in directory: URL) async throws -> URL {
        let fileSystem = fileSystem

        return try await Self.runUserInitiated {
            let trimmedName = try Self.validateName(name)
            try Self.validateDirectory(directory, fileSystem: fileSystem)

            let folderURL = directory.appendingPathComponent(trimmedName, isDirectory: true)
            try Self.validateDestinationDoesNotExist(folderURL, fileSystem: fileSystem)

            do {
                try fileSystem.createDirectory(at: folderURL)
            } catch {
                throw FileOperationError.operationFailed("create folder", folderURL, Self.userReadableReason(for: error))
            }

            return folderURL
        }
    }

    nonisolated func createFile(named name: String, in directory: URL) async throws -> URL {
        let fileSystem = fileSystem

        return try await Self.runUserInitiated {
            let trimmedName = try Self.validateName(name)
            try Self.validateDirectory(directory, fileSystem: fileSystem)

            let fileURL = directory.appendingPathComponent(trimmedName, isDirectory: false)
            try Self.validateDestinationDoesNotExist(fileURL, fileSystem: fileSystem)

            guard fileSystem.createFile(at: fileURL) else {
                throw FileOperationError.operationFailed("create file", fileURL, "The operation could not be completed.")
            }

            return fileURL
        }
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
        conflictResolution: FileConflictResolution,
        fileSystem: any FileSystemOperating
    ) throws -> [TransferPlan] {
        guard !items.isEmpty else {
            throw FileOperationError.noItems
        }

        try validateWritableDirectory(destinationDirectory, fileSystem: fileSystem)
        var reservedDestinationIdentities: Set<DestinationIdentity> = []

        return try items.compactMap { item -> TransferPlan? in
            try Task.checkCancellation()
            try validateSourceExists(item.url, fileSystem: fileSystem)
            try validateTransferSafety(for: item, to: destinationDirectory)
            let destinationURL = destinationDirectory.appendingPathComponent(item.name, isDirectory: item.isDirectory)
            let plannedDestinationIdentity = destinationIdentity(for: destinationURL)
            let destinationIsReserved = reservedDestinationIdentities.contains(plannedDestinationIdentity)
            let existingDestinationURL = existingDestinationURL(for: destinationURL, fileSystem: fileSystem)

            guard existingDestinationURL != nil || destinationIsReserved else {
                reservedDestinationIdentities.insert(plannedDestinationIdentity)
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

                let replacementTargetURL = existingDestinationURL ?? destinationURL
                guard !urlsReferToSameFile(item.url, replacementTargetURL) &&
                    item.url.resolvingSymlinksInPath().standardizedFileURL != replacementTargetURL.resolvingSymlinksInPath().standardizedFileURL else {
                    throw FileOperationError.cannotReplaceItemWithItself(replacementTargetURL)
                }

                reservedDestinationIdentities.insert(plannedDestinationIdentity)
                return TransferPlan(item: item, destinationURL: replacementTargetURL, shouldReplaceExistingItem: true)
            case .keepBoth:
                let uniqueDestinationURL = uniqueCopyURL(
                    for: destinationURL,
                    reservedDestinationIdentities: reservedDestinationIdentities,
                    fileSystem: fileSystem
                )
                reservedDestinationIdentities.insert(destinationIdentity(for: uniqueDestinationURL))
                return TransferPlan(item: item, destinationURL: uniqueDestinationURL, shouldReplaceExistingItem: false)
            }
        }
    }

    private nonisolated static func copyReplacingDestination(
        plan: TransferPlan,
        fileSystem: any FileSystemOperating
    ) throws {
        let stagingURL = uniqueReplacementStagingURL(
            in: plan.destinationURL.deletingLastPathComponent(),
            isDirectory: plan.item.isDirectory,
            fileSystem: fileSystem
        )

        do {
            try fileSystem.copyItem(at: plan.item.url, to: stagingURL)
            try fileSystem.replaceItem(at: plan.destinationURL, withItemAt: stagingURL)
        } catch {
            try? fileSystem.removeItem(at: stagingURL)
            throw error
        }
    }

    private nonisolated static func moveReplacingDestination(
        plan: TransferPlan,
        fileSystem: any FileSystemOperating
    ) throws {
        let stagingURL = uniqueReplacementStagingURL(
            in: plan.destinationURL.deletingLastPathComponent(),
            isDirectory: plan.item.isDirectory,
            fileSystem: fileSystem
        )

        do {
            // Stage moves by copying first so the source remains in place until
            // the destination replacement has succeeded.
            try fileSystem.copyItem(at: plan.item.url, to: stagingURL)
            try fileSystem.replaceItem(at: plan.destinationURL, withItemAt: stagingURL)
            do {
                try fileSystem.removeItem(at: plan.item.url)
            } catch {
                throw SourceCleanupFailure(reason: Self.userReadableReason(for: error))
            }
        } catch {
            try? fileSystem.removeItem(at: stagingURL)
            throw error
        }
    }

    private nonisolated static func hasPotentialTransferConflict(
        itemNamesAndDirectoryHints: [(name: String, isDirectory: Bool)],
        to destinationDirectory: URL,
        fileSystem: any FileSystemOperating
    ) -> Bool {
        var reservedDestinationIdentities: Set<DestinationIdentity> = []

        for item in itemNamesAndDirectoryHints {
            let destinationURL = destinationDirectory.appendingPathComponent(
                item.name,
                isDirectory: item.isDirectory
            )
            let destinationIdentity = destinationIdentity(for: destinationURL)

            if reservedDestinationIdentities.contains(destinationIdentity) ||
                existingDestinationURL(for: destinationURL, fileSystem: fileSystem) != nil {
                return true
            }

            reservedDestinationIdentities.insert(destinationIdentity)
        }

        return false
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
        var destinationURLKeys: Set<String> = []
        let sourceURLs = Set(items.map { $0.url.standardizedFileURL })
        let sortedItems = sortedForBatchRename(items)

        guard Set(previewNames.map { $0.lowercased() }).count == previewNames.count else {
            throw FileOperationError.duplicateDestinationNames
        }

        return try zip(sortedItems, previewNames).map { item, newName in
            try Task.checkCancellation()
            _ = try validateName(newName)
            try validateSourceExists(item.url)

            let destinationURL = item.url
                .deletingLastPathComponent()
                .appendingPathComponent(newName, isDirectory: item.isDirectory)
            let standardizedDestinationURL = destinationURL.standardizedFileURL
            let destinationURLKey = standardizedDestinationURL.path.lowercased()

            guard destinationURLKeys.insert(destinationURLKey).inserted else {
                throw FileOperationError.duplicateDestinationNames
            }

            if standardizedDestinationURL != item.url.standardizedFileURL,
               FileManager.default.fileExists(atPath: destinationURL.path),
               !sourceURLs.contains(standardizedDestinationURL),
               !items.contains(where: { urlsReferToSameFile($0.url, destinationURL) }) {
                throw FileOperationError.destinationExists(destinationURL)
            }

            return RenamePlan(item: item, destinationURL: destinationURL)
        }
    }

    private nonisolated static func performBatchRename(_ plans: [RenamePlan]) throws {
        let activePlans = plans.filter {
            $0.item.url.standardizedFileURL != $0.destinationURL.standardizedFileURL
        }

        guard !activePlans.isEmpty else {
            return
        }

        let stagedPlans = try temporaryRenamePlans(for: activePlans)
        var movedToTemporaryURLs: [StagedRenamePlan] = []

        do {
            for stagedPlan in stagedPlans {
                try Task.checkCancellation()
                try FileManager.default.moveItem(at: stagedPlan.plan.item.url, to: stagedPlan.temporaryURL)
                movedToTemporaryURLs.append(stagedPlan)
            }
        } catch is CancellationError {
            restoreTemporaryRenames(movedToTemporaryURLs)
            throw CancellationError()
        } catch {
            restoreTemporaryRenames(movedToTemporaryURLs)
            let failedURL = stagedPlans
                .first { !FileManager.default.fileExists(atPath: $0.temporaryURL.path) }
                .map(\.plan.item.url) ?? activePlans.first?.item.url ?? plans.first?.item.url
            throw FileOperationError.operationFailed(
                "rename",
                failedURL ?? URL(filePath: "/"),
                Self.userReadableReason(for: error)
            )
        }

        var completedFinalRenames: [StagedRenamePlan] = []

        do {
            for stagedPlan in stagedPlans {
                try Task.checkCancellation()
                try FileManager.default.moveItem(at: stagedPlan.temporaryURL, to: stagedPlan.plan.destinationURL)
                completedFinalRenames.append(stagedPlan)
            }
        } catch is CancellationError {
            rollbackBatchRename(
                completedFinalRenames: completedFinalRenames,
                stagedPlans: stagedPlans
            )
            throw CancellationError()
        } catch {
            rollbackBatchRename(
                completedFinalRenames: completedFinalRenames,
                stagedPlans: stagedPlans
            )
            let failedPlan = stagedPlans.first {
                FileManager.default.fileExists(atPath: $0.temporaryURL.path)
            }?.plan ?? activePlans.first ?? plans.first
            guard let failedPlan else {
                return
            }

            throw FileOperationError.operationFailed(
                "rename",
                failedPlan.item.url,
                "\(Self.userReadableReason(for: error)) The batch rename was rolled back where possible."
            )
        }
    }

    private nonisolated static func temporaryRenamePlans(for plans: [RenamePlan]) throws -> [StagedRenamePlan] {
        var reservedTemporaryURLs: Set<URL> = []

        return try plans.map { plan in
            try Task.checkCancellation()
            let temporaryURL = uniqueTemporaryRenameURL(
                in: plan.item.url.deletingLastPathComponent(),
                isDirectory: plan.item.isDirectory,
                reservedURLs: reservedTemporaryURLs
            )
            reservedTemporaryURLs.insert(temporaryURL.standardizedFileURL)

            return StagedRenamePlan(plan: plan, temporaryURL: temporaryURL)
        }
    }

    private nonisolated static func renameViaTemporaryURL(item: FileItem, to destinationURL: URL) throws -> URL {
        let temporaryURL = uniqueTemporaryRenameURL(
            in: item.url.deletingLastPathComponent(),
            isDirectory: item.isDirectory,
            reservedURLs: []
        )

        do {
            try FileManager.default.moveItem(at: item.url, to: temporaryURL)
        } catch {
            throw FileOperationError.operationFailed("rename", item.url, Self.userReadableReason(for: error))
        }

        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            do {
                try FileManager.default.moveItem(at: temporaryURL, to: item.url)
            } catch {
                throw FileOperationError.operationFailed(
                    "rename",
                    item.url,
                    "\(Self.userReadableReason(for: error)) The item remains at \(temporaryURL.lastPathComponent)."
                )
            }

            throw FileOperationError.operationFailed("rename", item.url, Self.userReadableReason(for: error))
        }

        return destinationURL
    }

    private nonisolated static func restoreTemporaryRenames(_ stagedPlans: [StagedRenamePlan]) {
        for stagedPlan in stagedPlans.reversed() {
            guard FileManager.default.fileExists(atPath: stagedPlan.temporaryURL.path),
                  !FileManager.default.fileExists(atPath: stagedPlan.plan.item.url.path) else {
                continue
            }

            try? FileManager.default.moveItem(at: stagedPlan.temporaryURL, to: stagedPlan.plan.item.url)
        }
    }

    private nonisolated static func rollbackBatchRename(
        completedFinalRenames: [StagedRenamePlan],
        stagedPlans: [StagedRenamePlan]
    ) {
        for stagedPlan in completedFinalRenames.reversed() {
            guard FileManager.default.fileExists(atPath: stagedPlan.plan.destinationURL.path),
                  !FileManager.default.fileExists(atPath: stagedPlan.plan.item.url.path) else {
                continue
            }

            try? FileManager.default.moveItem(
                at: stagedPlan.plan.destinationURL,
                to: stagedPlan.plan.item.url
            )
        }

        let remainingTemporaryRenames = stagedPlans.filter {
            FileManager.default.fileExists(atPath: $0.temporaryURL.path)
        }
        restoreTemporaryRenames(remainingTemporaryRenames)
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

    private nonisolated static func uniqueCopyURL(
        for url: URL,
        reservedDestinationIdentities: Set<DestinationIdentity>,
        fileSystem: any FileSystemOperating
    ) -> URL {
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

            if !reservedDestinationIdentities.contains(destinationIdentity(for: candidateURL)),
               existingDestinationURL(for: candidateURL, fileSystem: fileSystem) == nil {
                return candidateURL
            }

            copyNumber += 1
        }
    }

    private nonisolated static func uniqueArchiveURL(in directoryURL: URL, baseName: String) -> URL {
        var archiveNumber = 1

        while true {
            let candidateName = archiveNumber == 1 ? baseName : "\(baseName) \(archiveNumber)"
            let candidateURL = directoryURL
                .appendingPathComponent("\(candidateName).zip", isDirectory: false)

            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }

            archiveNumber += 1
        }
    }

    private nonisolated static func createTemporaryArchiveDirectory(
        in directoryURL: URL,
        reportingFailureFor archiveURL: URL,
        fileSystem: any FileSystemOperating
    ) throws -> URL {
        while true {
            let temporaryDirectoryURL = directoryURL.appendingPathComponent(
                ".openpane-archive-\(UUID().uuidString)",
                isDirectory: true
            )

            do {
                try fileSystem.createDirectory(at: temporaryDirectoryURL)
                return temporaryDirectoryURL
            } catch {
                if isDestinationExistsError(error) {
                    continue
                }

                throw FileOperationError.operationFailed(
                    "compress",
                    archiveURL,
                    userReadableReason(for: error)
                )
            }
        }
    }

    private nonisolated static func publishArchive(
        at temporaryArchiveURL: URL,
        initiallyTo initialArchiveURL: URL,
        destination: ArchiveDestination,
        fileSystem: any FileSystemOperating
    ) throws -> URL {
        var candidateURL = initialArchiveURL

        while true {
            do {
                try fileSystem.moveItemExclusively(at: temporaryArchiveURL, to: candidateURL)
                return candidateURL
            } catch {
                if isDestinationExistsError(error) {
                    candidateURL = uniqueArchiveURL(
                        in: destination.directoryURL,
                        baseName: destination.baseName
                    )
                    continue
                }

                throw FileOperationError.operationFailed(
                    "compress",
                    candidateURL,
                    userReadableReason(for: error)
                )
            }
        }
    }

    private nonisolated static func archiveCreationFailure(
        for archiveURL: URL,
        error: Error
    ) -> FileOperationError {
        if case let FileOperationError.operationFailed(_, _, reason) = error {
            return .operationFailed("compress", archiveURL, reason)
        }

        return .operationFailed("compress", archiveURL, userReadableReason(for: error))
    }

    private nonisolated static func isDestinationExistsError(_ error: Error) -> Bool {
        if let posixError = error as? POSIXError {
            return posixError.code == .EEXIST
        }

        let nsError = error as NSError
        return (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EEXIST))
            || (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteFileExistsError)
    }

    private nonisolated static func uniqueTemporaryRenameURL(
        in directoryURL: URL,
        isDirectory: Bool,
        reservedURLs: Set<URL>
    ) -> URL {
        while true {
            let candidateURL = directoryURL.appendingPathComponent(
                ".openpane-rename-\(UUID().uuidString).tmp",
                isDirectory: isDirectory
            )

            if !reservedURLs.contains(candidateURL.standardizedFileURL),
               !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
    }

    private nonisolated static func uniqueReplacementStagingURL(
        in directoryURL: URL,
        isDirectory: Bool,
        fileSystem: any FileSystemOperating
    ) -> URL {
        while true {
            let candidateURL = directoryURL.appendingPathComponent(
                ".openpane-replace-\(UUID().uuidString).tmp",
                isDirectory: isDirectory
            )

            if existingDestinationURL(for: candidateURL, fileSystem: fileSystem) == nil {
                return candidateURL
            }
        }
    }

    private nonisolated static func uniqueTransferStagingURL(
        in directoryURL: URL,
        isDirectory: Bool,
        fileSystem: any FileSystemOperating
    ) -> URL {
        while true {
            let candidateURL = directoryURL.appendingPathComponent(
                ".openpane-transfer-\(UUID().uuidString).tmp",
                isDirectory: isDirectory
            )

            if existingDestinationURL(for: candidateURL, fileSystem: fileSystem) == nil {
                return candidateURL
            }
        }
    }

    private nonisolated static func existingDestinationURL(
        for destinationURL: URL,
        fileSystem: any FileSystemOperating
    ) -> URL? {
        if fileSystem.fileExists(at: destinationURL) {
            return destinationURL
        }

        let requestedDestinationIdentity = destinationIdentity(for: destinationURL)
        let parentURL = destinationURL.deletingLastPathComponent()
        guard let siblingURLs = try? fileSystem.contentsOfDirectory(at: parentURL) else {
            return nil
        }

        return siblingURLs.first {
            destinationIdentity(for: $0) == requestedDestinationIdentity
        }
    }

    private nonisolated static func destinationIdentity(for url: URL) -> DestinationIdentity {
        DestinationIdentity(
            parentIdentity: canonicalURLIdentity(for: url.deletingLastPathComponent()),
            nameKey: normalizedDestinationNameKey(url.lastPathComponent)
        )
    }

    private nonisolated static func canonicalURLIdentity(for url: URL) -> String {
        if let resourceIdentity = resourceIdentity(for: url) {
            return resourceIdentity
        }

        return "path:\(url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased())"
    }

    private nonisolated static func resourceIdentity(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey]),
              let fileIdentifier = values.fileResourceIdentifier as? NSObject,
              let volumeIdentifier = values.volumeIdentifier as? NSObject else {
            return nil
        }

        return "resource:\(volumeIdentifier.description):\(fileIdentifier.description)"
    }

    private nonisolated static func normalizedDestinationNameKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private nonisolated static func validateSourceExists(
        _ url: URL,
        fileSystem: any FileSystemOperating = FileManagerFileSystem()
    ) throws {
        guard fileSystem.fileExists(at: url) else {
            throw FileOperationError.sourceDoesNotExist(url)
        }
    }

    private nonisolated static func validateDirectory(
        _ url: URL,
        fileSystem: any FileSystemOperating = FileManagerFileSystem()
    ) throws {
        var isDirectory: ObjCBool = false

        guard fileSystem.fileExists(at: url, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileOperationError.destinationIsNotDirectory(url)
        }
    }

    private nonisolated static func validateWritableDirectory(
        _ url: URL,
        fileSystem: any FileSystemOperating = FileManagerFileSystem()
    ) throws {
        try validateDirectory(url, fileSystem: fileSystem)

        guard fileSystem.isWritableFile(at: url) else {
            throw FileOperationError.destinationIsNotWritable(url)
        }
    }

    private nonisolated static func validateTransferSafety(for item: FileItem, to destinationDirectory: URL) throws {
        let standardizedSourceURL = item.url.standardizedFileURL
        let standardizedDestinationDirectory = destinationDirectory.standardizedFileURL
        let resolvedSourceURL = item.url.resolvingSymlinksInPath().standardizedFileURL
        let resolvedDestinationDirectory = destinationDirectory.resolvingSymlinksInPath().standardizedFileURL
        let destinationURL = destinationDirectory
            .appendingPathComponent(item.name, isDirectory: item.isDirectory)
            .standardizedFileURL

        guard standardizedSourceURL != destinationURL,
              resolvedSourceURL != destinationURL.resolvingSymlinksInPath().standardizedFileURL else {
            throw FileOperationError.cannotReplaceItemWithItself(item.url)
        }

        guard item.isDirectory else {
            return
        }

        if standardizedSourceURL == standardizedDestinationDirectory ||
            standardizedDestinationDirectory.isDescendant(of: standardizedSourceURL) ||
            resolvedSourceURL == resolvedDestinationDirectory ||
            resolvedDestinationDirectory.isDescendant(of: resolvedSourceURL) {
            throw FileOperationError.cannotPlaceFolderInsideItself(item.url)
        }
    }

    private nonisolated static func validateDestinationDoesNotExist(
        _ url: URL,
        fileSystem: any FileSystemOperating = FileManagerFileSystem()
    ) throws {
        guard existingDestinationURL(for: url, fileSystem: fileSystem) == nil else {
            throw FileOperationError.destinationExists(url)
        }
    }

    private nonisolated static func urlsReferToSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        do {
            let lhsValues = try lhs.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey])
            let rhsValues = try rhs.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey])

            if let lhsFileIdentifier = lhsValues.fileResourceIdentifier as? NSObject,
               let rhsFileIdentifier = rhsValues.fileResourceIdentifier as? NSObject,
               let lhsVolumeIdentifier = lhsValues.volumeIdentifier as? NSObject,
               let rhsVolumeIdentifier = rhsValues.volumeIdentifier as? NSObject {
                return lhsFileIdentifier.isEqual(rhsFileIdentifier) && lhsVolumeIdentifier.isEqual(rhsVolumeIdentifier)
            }
        } catch {
            return false
        }

        return lhs.resolvingSymlinksInPath().standardizedFileURL == rhs.resolvingSymlinksInPath().standardizedFileURL
    }

    private nonisolated static func partialFailureReason(
        for error: Error,
        completedCount: Int,
        totalCount: Int,
        completedVerb: String
    ) -> String {
        let baseReason = Self.userReadableReason(for: error)

        guard completedCount > 0 else {
            return baseReason
        }

        let itemText = completedCount == 1 ? "item was" : "items were"
        return "\(baseReason) \(completedCount) of \(totalCount) \(itemText) already \(completedVerb) before this failed."
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
