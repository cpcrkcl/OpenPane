//
//  QuickLookPreviewView.swift
//  OpenPane
//

import QuickLookUI
import SwiftUI

/// Hosts the system Quick Look renderer inside the preview sidebar. Quick Look
/// remains responsible for document scrolling, image zooming, and media
/// controls, while OpenPane controls when the selected item is refreshed.
struct QuickLookPreviewView: NSViewRepresentable {
    let url: URL
    let revision: FilePreviewRevision

    func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView(frame: .zero, style: .normal)
        previewView?.autostarts = false
        previewView?.shouldCloseWithWindow = false
        previewView?.previewItem = url as NSURL
        context.coordinator.renderedURL = url
        context.coordinator.renderedRevision = revision
        return previewView ?? QLPreviewView(frame: .zero)!
    }

    func updateNSView(_ previewView: QLPreviewView, context: Context) {
        previewView.autostarts = false

        guard context.coordinator.renderedURL != url ||
                context.coordinator.renderedRevision != revision else {
            return
        }

        let changedURL = context.coordinator.renderedURL != url
        context.coordinator.renderedURL = url
        context.coordinator.renderedRevision = revision

        if changedURL {
            previewView.previewItem = url as NSURL
        } else {
            previewView.refreshPreviewItem()
        }
    }

    static func dismantleNSView(_ previewView: QLPreviewView, coordinator: Coordinator) {
        previewView.previewItem = nil
        previewView.close()
        coordinator.renderedURL = nil
        coordinator.renderedRevision = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        fileprivate var renderedURL: URL?
        fileprivate var renderedRevision: FilePreviewRevision?
    }
}
