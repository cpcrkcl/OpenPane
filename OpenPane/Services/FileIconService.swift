//
//  FileIconService.swift
//  OpenPane
//
//  Cache policy: content-type keys for ordinary documents and folders, plus
//  path-specific keys for applications and packages whose icons are unique.
//  The cache holds 256 entries and 4 MiB by default. Entries use deterministic
//  FIFO eviction in addition to NSCache's memory-pressure eviction.
//

@preconcurrency import AppKit
import Foundation
import UniformTypeIdentifiers

nonisolated struct LoadedFileIcon: @unchecked Sendable {
    let image: NSImage
    let cost: Int
}

nonisolated enum FileIconLookup: Hashable, Sendable {
    case file(URL)
    case contentType(String)
}

typealias FileIconLoader = @Sendable (FileIconLookup) async -> LoadedFileIcon

@MainActor
protocol FileIconServicing {
    func cachedIcon(for item: FileItem) -> NSImage?
    func icon(for item: FileItem) async -> NSImage
    func invalidateIcon(for item: FileItem)
}

extension FileIconServicing {
    func invalidateIcon(for item: FileItem) {}
}

@MainActor
final class FileIconService: FileIconServicing {
    private struct IconDescriptor {
        let cacheKey: String
        let lookup: FileIconLookup
    }

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
        let key = iconDescriptor(for: item).cacheKey
        guard let image = cache.object(forKey: key as NSString) else {
            removeCacheTracking(for: key)
            return nil
        }
        return image
    }

    func icon(for item: FileItem) async -> NSImage {
        let descriptor = iconDescriptor(for: item)
        let key = descriptor.cacheKey
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
            let lookup = descriptor.lookup
            let loader = iconLoader
            // The detached task is retained and awaited below. This keeps the
            // AppKit filesystem lookup off the main actor while preserving
            // request deduplication and a single publication point.
            let task = Task.detached(priority: .utility) {
                await loader(lookup)
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
        let inFlightRequests = inFlightRequestsByKey.values
        inFlightRequestsByKey.removeAll(keepingCapacity: true)
        inFlightRequests.forEach { $0.task.cancel() }
    }

    func invalidateIcon(for item: FileItem) {
        let key = iconDescriptor(for: item).cacheKey
        cache.removeObject(forKey: key as NSString)
        removeCacheTracking(for: key)
        inFlightRequestsByKey.removeValue(forKey: key)?.task.cancel()
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

    private func iconDescriptor(for item: FileItem) -> IconDescriptor {
        let fileExtension = item.url.pathExtension.lowercased()

        if requiresFileSpecificIcon(item, fileExtension: fileExtension) {
            let url = item.url.standardizedFileURL
            return IconDescriptor(
                cacheKey: "file:\(url.path)",
                lookup: .file(url)
            )
        }

        let contentType: UTType
        if item.isDirectory {
            contentType = .folder
        } else if let typeIdentifier = item.typeIdentifier,
                  let itemType = UTType(typeIdentifier) {
            contentType = itemType
        } else if !fileExtension.isEmpty,
                  let extensionType = UTType(filenameExtension: fileExtension) {
            contentType = extensionType
        } else {
            contentType = .data
        }

        return IconDescriptor(
            cacheKey: "type:\(contentType.identifier)",
            lookup: .contentType(contentType.identifier)
        )
    }

    private func requiresFileSpecificIcon(_ item: FileItem, fileExtension: String) -> Bool {
        guard item.isDirectory else {
            return false
        }

        if fileExtension == "app" {
            return true
        }

        let contentType = item.typeIdentifier.flatMap(UTType.init)
            ?? UTType(filenameExtension: fileExtension)
        return contentType?.conforms(to: .application) == true ||
            contentType?.conforms(to: .package) == true ||
            contentType?.conforms(to: .bundle) == true
    }

    private nonisolated static func loadIconFromWorkspace(
        for lookup: FileIconLookup
    ) async -> LoadedFileIcon {
        let sourceImage: NSImage
        switch lookup {
        case .file(let url):
            sourceImage = NSWorkspace.shared.icon(forFile: url.path)
        case .contentType(let identifier):
            let contentType = UTType(identifier) ?? .data
            sourceImage = NSWorkspace.shared.icon(for: contentType)
        }

        let image = (sourceImage.copy() as? NSImage) ?? sourceImage
        image.size = NSSize(width: 16, height: 16)
        return LoadedFileIcon(image: image, cost: 16 * 16 * 4)
    }
}
