//
//  VideoThumbnailView.swift
//  OpenPane
//

import AppKit
import SwiftUI

struct VideoThumbnailView: View {
    let url: URL
    let revision: FilePreviewRevision

    @State private var thumbnail: NSImage?
    @State private var isLoading = true

    private let thumbnailService: any VideoThumbnailServicing

    @MainActor
    init(
        url: URL,
        revision: FilePreviewRevision,
        thumbnailService: any VideoThumbnailServicing = VideoThumbnailService.shared
    ) {
        self.url = url
        self.revision = revision
        self.thumbnailService = thumbnailService
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CatppuccinMochaTheme.base

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Video thumbnail for \(url.lastPathComponent)")
                } else {
                    genericThumbnail
                }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.black.opacity(0.48), in: Capsule())
                }
            }
            .task(id: revision) {
                thumbnail = nil
                isLoading = true
                let requestedSize = CGSize(
                    width: max(1, geometry.size.width),
                    height: max(1, geometry.size.height)
                )
                let image = await thumbnailService.thumbnail(
                    for: url,
                    revision: revision,
                    size: requestedSize,
                    scale: NSScreen.main?.backingScaleFactor ?? 2
                )
                guard !Task.isCancelled else { return }
                thumbnail = image
                isLoading = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("video-thumbnail-preview")
    }

    private var genericThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(CatppuccinMochaTheme.mantle)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(CatppuccinMochaTheme.surface1, lineWidth: 1)
                }

            VStack(spacing: 10) {
                Image(systemName: "movieclapper")
                    .font(.system(size: 54, weight: .light))
                Text("Video")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(CatppuccinMochaTheme.mutedText)
        }
        .padding(18)
        .accessibilityLabel("Generic video thumbnail")
    }
}
