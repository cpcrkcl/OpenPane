//
//  DirectoryMonitoringService.swift
//  OpenPane
//
//  Created by Codex on 6/30/26.
//

import Darwin
import Foundation

nonisolated protocol DirectoryMonitorToken: Sendable {
    nonisolated func cancel()
}

nonisolated protocol DirectoryMonitorServicing: Sendable {
    nonisolated func monitorDirectory(
        at url: URL,
        onChange: @escaping @Sendable () -> Void
    ) -> any DirectoryMonitorToken
}

nonisolated struct DirectoryMonitoringService: DirectoryMonitorServicing {
    nonisolated func monitorDirectory(
        at url: URL,
        onChange: @escaping @Sendable () -> Void
    ) -> any DirectoryMonitorToken {
        let fileDescriptor = open((url as NSURL).fileSystemRepresentation, O_EVTONLY)

        guard fileDescriptor >= 0 else {
            return NoopDirectoryMonitorToken()
        }

        let queue = DispatchQueue(
            label: "com.openpane.directory-monitor.\(UUID().uuidString)",
            qos: .userInitiated
        )
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [
                .write,
                .delete,
                .rename,
                .extend,
                .attrib,
                .link,
                .revoke
            ],
            queue: queue
        )
        let token = DispatchSourceDirectoryMonitorToken(source: source)

        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            close(fileDescriptor)
        }
        source.resume()

        return token
    }
}

private final class NoopDirectoryMonitorToken: DirectoryMonitorToken, @unchecked Sendable {
    nonisolated func cancel() {}
}

private final class DispatchSourceDirectoryMonitorToken: DirectoryMonitorToken, @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    private let lock = NSLock()
    private var isCancelled = false

    init(source: DispatchSourceFileSystemObject) {
        self.source = source
    }

    deinit {
        cancel()
    }

    nonisolated func cancel() {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !isCancelled else {
            return
        }

        isCancelled = true
        source.cancel()
    }
}
