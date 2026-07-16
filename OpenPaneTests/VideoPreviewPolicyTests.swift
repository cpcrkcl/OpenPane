//
//  VideoPreviewPolicyTests.swift
//  OpenPaneTests
//

import Testing
@testable import OpenPane

struct VideoPreviewPolicyTests {
    @Test func recognizesMoviesFromTypeOrExtension() {
        #expect(VideoPreviewPolicy.isVideo(typeIdentifier: "public.mpeg-4", fileExtension: ""))
        #expect(VideoPreviewPolicy.isVideo(typeIdentifier: nil, fileExtension: "mov"))
        #expect(!VideoPreviewPolicy.isVideo(typeIdentifier: "public.jpeg", fileExtension: "jpg"))
    }

    @Test func largeMoviesSkipFormatInspection() {
        let limit = VideoPreviewPolicy.maximumFormatInspectionByteCount

        #expect(VideoPreviewPolicy.shouldInspectFormat(
            typeIdentifier: nil,
            fileExtension: "mp4",
            logicalSize: limit
        ))
        #expect(!VideoPreviewPolicy.shouldInspectFormat(
            typeIdentifier: nil,
            fileExtension: "mp4",
            logicalSize: limit + 1
        ))
        #expect(!VideoPreviewPolicy.shouldInspectFormat(
            typeIdentifier: nil,
            fileExtension: "mp4",
            logicalSize: nil
        ))
    }
}
