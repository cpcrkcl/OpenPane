//
//  QuickLookPreviewServiceTests.swift
//  OpenPaneTests
//
//  Created by OpenAI on 6/30/26.
//

import Foundation
import Testing
@testable import OpenPane

struct QuickLookPreviewServiceTests {
    @Test func previewItemReturnsURLForValidIndex() throws {
        let previewURL = URL(filePath: "/tmp/preview.txt")

        let item = try #require(QuickLookPreviewService.previewItem(from: [previewURL], at: 0) as? NSURL)

        #expect(item as URL == previewURL)
    }

    @Test func previewItemReturnsNilForOutOfBoundsIndex() {
        let previewURL = URL(filePath: "/tmp/preview.txt")

        #expect(QuickLookPreviewService.previewItem(from: [previewURL], at: -1) == nil)
        #expect(QuickLookPreviewService.previewItem(from: [previewURL], at: 1) == nil)
        #expect(QuickLookPreviewService.previewItem(from: [], at: 0) == nil)
    }
}
