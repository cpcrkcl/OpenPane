//
//  VideoThumbnailService.swift
//  OpenPane
//

@preconcurrency import AppKit
import Foundation
@preconcurrency import QuickLookThumbnailing

@MainActor
protocol VideoThumbnailServicing {
    func thumbnail(
        for url: URL,
        revision: FilePreviewRevision,
        size: CGSize,
        scale: CGFloat
    ) async -> NSImage?
}

/// Requests only Quick Look's cached/fast low-quality representation. It never
/// asks the embedded preview panel to decode or play the selected movie.
@MainActor
final class VideoThumbnailService: VideoThumbnailServicing {
    static let shared = VideoThumbnailService()

    private let cache = NSCache<NSString, NSImage>()

    init(maximumCacheEntryCount: Int = 32) {
        cache.countLimit = max(1, maximumCacheEntryCount)
    }

    func thumbnail(
        for url: URL,
        revision: FilePreviewRevision,
        size: CGSize,
        scale: CGFloat
    ) async -> NSImage? {
        let key = cacheKey(for: url, revision: revision, size: size, scale: scale)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .lowQualityThumbnail
        )
        let generator = QLThumbnailGenerator.shared
        let image: NSImage? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                generator.generateBestRepresentation(for: request) { representation, _ in
                    continuation.resume(returning: representation?.nsImage)
                }
            }
        } onCancel: {
            generator.cancel(request)
        }

        guard !Task.isCancelled, let image else {
            return nil
        }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    private func cacheKey(
        for url: URL,
        revision: FilePreviewRevision,
        size: CGSize,
        scale: CGFloat
    ) -> String {
        [
            url.standardizedFileURL.path,
            revision.resourceIdentifier ?? "—",
            revision.logicalSize.map(String.init) ?? "—",
            revision.contentModificationDate?.timeIntervalSinceReferenceDate.description ?? "—",
            "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))@\(scale)"
        ].joined(separator: "|")
    }
}
