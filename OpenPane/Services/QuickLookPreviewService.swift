//
//  QuickLookPreviewService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/6/26.
//

import Foundation
import Quartz

@MainActor
protocol QuickLookPreviewServicing: AnyObject {
    func preview(url: URL)
}

@MainActor
final class QuickLookPreviewService: NSObject, QuickLookPreviewServicing, QLPreviewPanelDataSource {
    static let shared = QuickLookPreviewService()

    private var previewURLs: [URL] = []

    func preview(url: URL) {
        previewURLs = [url]

        guard let panel = QLPreviewPanel.shared() else {
            return
        }

        panel.dataSource = self
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        Self.previewItem(from: previewURLs, at: index)
    }

    nonisolated static func previewItem(from previewURLs: [URL], at index: Int) -> QLPreviewItem? {
        guard previewURLs.indices.contains(index) else {
            return nil
        }

        return previewURLs[index] as NSURL
    }
}
