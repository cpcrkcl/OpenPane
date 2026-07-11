//
//  FileIconService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/6/26.
//

import AppKit
import Foundation

@MainActor
protocol FileIconServicing {
    func icon(for item: FileItem) -> NSImage
}

@MainActor
final class FileIconService: FileIconServicing {
    static let shared = FileIconService()

    private var cachedIconsByKey: [String: NSImage] = [:]
    private var cacheKeysInInsertionOrder: [String] = []
    private let maximumCacheEntryCount: Int

    #if DEBUG
    var cachedIconCount: Int { cachedIconsByKey.count }
    #endif

    init(maximumCacheEntryCount: Int = 256) {
        self.maximumCacheEntryCount = max(1, maximumCacheEntryCount)
    }

    func icon(for item: FileItem) -> NSImage {
        let key = cacheKey(for: item)

        if let cachedIcon = cachedIconsByKey[key] {
            return cachedIcon
        }

        #if DEBUG
        PerformanceDiagnostics.shared.recordIconCacheMiss()
        #endif

        let icon = resizedCopy(of: NSWorkspace.shared.icon(forFile: item.url.path))
        if cachedIconsByKey.count >= maximumCacheEntryCount,
           let oldestKey = cacheKeysInInsertionOrder.first {
            cachedIconsByKey[oldestKey] = nil
            cacheKeysInInsertionOrder.removeFirst()
        }
        cachedIconsByKey[key] = icon
        cacheKeysInInsertionOrder.append(key)

        return icon
    }

    private func resizedCopy(of image: NSImage) -> NSImage {
        let copiedImage = (image.copy() as? NSImage) ?? image
        copiedImage.size = NSSize(width: 16, height: 16)
        return copiedImage
    }

    private func cacheKey(for item: FileItem) -> String {
        if item.isDirectory {
            return "directory"
        }

        let fileExtension = item.url.pathExtension.lowercased()
        if !fileExtension.isEmpty {
            return "extension:\(fileExtension)"
        }

        if let typeIdentifier = item.typeIdentifier {
            return "type:\(typeIdentifier)"
        }

        return "file"
    }
}
