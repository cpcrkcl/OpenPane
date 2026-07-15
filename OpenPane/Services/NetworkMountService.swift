//
//  NetworkMountService.swift
//  OpenPane
//
//  Created by Codex on 7/11/26.
//

import Foundation
@preconcurrency import NetFS

nonisolated enum NetworkMountError: LocalizedError, Equatable, Sendable {
    case mountFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .mountFailed(let status):
            return "The network share could not be mounted (status \(status))."
        }
    }
}

nonisolated protocol NetworkMounting: Sendable {
    nonisolated func mount(serverURL: URL) async throws -> [URL]
}

/// NetFS-backed SMB mounting. NetFS presents the native macOS authentication
/// UI when needed; this service deliberately passes no credentials itself.
nonisolated struct NetworkMountService: NetworkMounting {
    private let queue: DispatchQueue

    nonisolated init(
        queue: DispatchQueue = DispatchQueue(
            label: "com.openpane.network-mount",
            qos: .userInitiated
        )
    ) {
        self.queue = queue
    }

    nonisolated func mount(serverURL: URL) async throws -> [URL] {
        let normalizedURL = try NetworkServerAddress.normalize(serverURL)
        try Task.checkCancellation()
        let request = NetFSMountRequest()
        let queue = self.queue

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[URL], Error>) in
                request.start(
                    url: normalizedURL,
                    queue: queue,
                    continuation: continuation
                )
            }
        } onCancel: {
            request.cancel()
        }
    }
}

private nonisolated final class NetFSMountRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[URL], Error>?
    private var requestID: AsyncRequestID?
    private var isFinished = false

    nonisolated func start(
        url: URL,
        queue: DispatchQueue,
        continuation: CheckedContinuation<[URL], Error>
    ) {
        let shouldStart = lock.withLock {
            guard !isFinished else {
                return false
            }

            self.continuation = continuation
            return true
        }

        // Cancellation handlers may run before the continuation is installed.
        // In that ordering, `cancel()` has already moved the request to its
        // terminal state and had no continuation to resume. Never start NetFS
        // or strand the newly supplied continuation in that state.
        guard shouldStart else {
            continuation.resume(throwing: CancellationError())
            return
        }

        var requestID: AsyncRequestID?
        let status = NetFSMountURLAsync(
            url as CFURL,
            nil,
            nil,
            nil,
            nil,
            nil,
            &requestID,
            queue
        ) { [weak self] status, _, mountpoints in
            self?.complete(status: status, mountpoints: mountpoints)
        }

        if status != 0 {
            complete(status: status, mountpoints: nil)
            return
        }

        var shouldCancel = false
        lock.withLock {
            if isFinished {
                shouldCancel = requestID != nil
            } else {
                self.requestID = requestID
            }
        }

        if shouldCancel, let requestID {
            _ = NetFSMountURLCancel(requestID)
        }
    }

    nonisolated func cancel() {
        let state: (AsyncRequestID?, CheckedContinuation<[URL], Error>?) = lock.withLock {
            guard !isFinished else {
                return (nil, nil)
            }

            isFinished = true
            let state = (requestID, continuation)
            requestID = nil
            continuation = nil
            return state
        }

        if let requestID = state.0 {
            _ = NetFSMountURLCancel(requestID)
        }

        state.1?.resume(throwing: CancellationError())
    }

    private nonisolated func complete(status: Int32, mountpoints: CFArray?) {
        let continuation: CheckedContinuation<[URL], Error>? = lock.withLock {
            guard !isFinished else {
                return nil
            }

            isFinished = true
            let continuation = self.continuation
            self.continuation = nil
            requestID = nil
            return continuation
        }

        guard let continuation else {
            return
        }

        if status == 0 {
            continuation.resume(returning: Self.mountURLs(from: mountpoints))
        } else {
            continuation.resume(throwing: NetworkMountError.mountFailed(status: status))
        }
    }

    private nonisolated static func mountURLs(from mountpoints: CFArray?) -> [URL] {
        guard let mountpoints,
              let paths = mountpoints as? [String] else {
            return []
        }

        return paths
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
    }
}
