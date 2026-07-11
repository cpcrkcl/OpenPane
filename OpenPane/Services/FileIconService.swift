//
//  FileIconService.swift
//  OpenPane
//
//  Cache policy: extension/type/directory key, 256 entries and 4 MiB by
//  default. Entries use deterministic FIFO eviction in addition to NSCache's
//  memory-pressure eviction. Filesystem icon lookup never occurs on the main
//  actor; main-actor reads only consult NSCache and the in-flight table.
//

@preconcurrency import AppKit
import Foundation

nonisolated struct LoadedFileIcon: @unchecked Sendable {
    let image: NSImage
    let cost: Int
}

typealias FileIconLoader = @Sendable (URL) async -> LoadedFileIcon

@MainActor
protocol FileIconServicing {
    func cachedIcon(for item: FileItem) -> NSImage?
    func icon(for item: FileItem) async -> NSImage
}

@MainActor
final class FileIconService: FileIconServicing {
    private struct InFlightRequest {
        let id: UUID
        let task: Task<LoadedFileIcon, Never>
    }

    static let shared = FileIconService()

    private let cache = NSCache<NSString, NSImage>()
    private var cacheKeysInInsertionOrder: [String] = []
    private var cacheCostsByKey: [String: Int] = [:]
    private var currentCacheCost = 0
    private var inFlightRequestsByKey: [String: InFlightRequest] = [:]
    private let maximumCacheEntryCount: Int
    private let maximumCacheCost: Int
    private let iconLoader: FileIconLoader
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    #if DEBUG
    var cachedIconCount: Int { cacheCostsByKey.count }
    var inFlightRequestCount: Int { inFlightRequestsByKey.count }
    var cacheLimits: (count: Int, cost: Int) { (maximumCacheEntryCount, maximumCacheCost) }
    #endif

    init(
        maximumCacheEntryCount: Int = 256,
        maximumCacheCost: Int = 4 * 1_024 * 1_024,
        observesMemoryPressure: Bool = true,
        iconLoader: @escaping FileIconLoader = FileIconService.loadIconFromWorkspace
    ) {
        self.maximumCacheEntryCount = max(1, maximumCacheEntryCount)
        self.maximumCacheCost = max(1, maximumCacheCost)
        self.iconLoader = iconLoader
        cache.countLimit = self.maximumCacheEntryCount
        cache.totalCostLimit = self.maximumCacheCost

        if observesMemoryPressure {
            installMemoryPressureHandler()
        }
    }

    func cachedIcon(for item: FileItem) -> NSImage? {
        let key = cacheKey(for: item)
        guard let image = cache.object(forKey: key as NSString) else {
            removeCacheTracking(for: key)
            return nil
        }
        return image
    }

    func icon(for item: FileItem) async -> NSImage {
        let key = cacheKey(for: item)
        if let cachedImage = cachedIcon(for: item) {
            return cachedImage
        }

        let request: InFlightRequest
        if let inFlightRequest = inFlightRequestsByKey[key] {
            request = inFlightRequest
        } else {
            #if DEBUG
            PerformanceDiagnostics.shared.recordIconCacheMiss()
            #endif

            let requestID = UUID()
            let url = item.url
            let loader = iconLoader
            // The detached task is retained and awaited below. This keeps the
            // AppKit filesystem lookup off the main actor while preserving
            // request deduplication and a single publication point.
            let task = Task.detached(priority: .utility) {
                await loader(url)
            }
            request = InFlightRequest(id: requestID, task: task)
            inFlightRequestsByKey[key] = request
        }

        let loadedIcon = await request.task.value
        if inFlightRequestsByKey[key]?.id == request.id {
            inFlightRequestsByKey[key] = nil
            insert(loadedIcon, forKey: key)
        }
        return cache.object(forKey: key as NSString) ?? loadedIcon.image
    }

    func removeAllCachedIcons() {
        cache.removeAllObjects()
        cacheKeysInInsertionOrder.removeAll(keepingCapacity: true)
        cacheCostsByKey.removeAll(keepingCapacity: true)
        currentCacheCost = 0
    }

    private func insert(_ loadedIcon: LoadedFileIcon, forKey key: String) {
        removeCacheTracking(for: key)
        let cost = min(max(1, loadedIcon.cost), maximumCacheCost)

        while !cacheKeysInInsertionOrder.isEmpty &&
              (cacheCostsByKey.count >= maximumCacheEntryCount || currentCacheCost + cost > maximumCacheCost) {
            evictOldestIcon()
        }

        cache.setObject(loadedIcon.image, forKey: key as NSString, cost: cost)
        cacheKeysInInsertionOrder.append(key)
        cacheCostsByKey[key] = cost
        currentCacheCost += cost
    }

    private func evictOldestIcon() {
        guard let oldestKey = cacheKeysInInsertionOrder.first else {
            return
        }
        cache.removeObject(forKey: oldestKey as NSString)
        removeCacheTracking(for: oldestKey)
    }

    private func removeCacheTracking(for key: String) {
        if let cost = cacheCostsByKey.removeValue(forKey: key) {
            currentCacheCost -= cost
        }
        cacheKeysInInsertionOrder.removeAll { $0 == key }
    }

    private func installMemoryPressureHandler() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.removeAllCachedIcons()
            }
        }
        source.resume()
        memoryPressureSource = source
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

    private nonisolated static func loadIconFromWorkspace(for url: URL) async -> LoadedFileIcon {
        let sourceImage = NSWorkspace.shared.icon(forFile: url.path)
        let image = (sourceImage.copy() as? NSImage) ?? sourceImage
        image.size = NSSize(width: 16, height: 16)
        return LoadedFileIcon(image: image, cost: 16 * 16 * 4)
    }
}
