//
//  WorkspaceSplitLayout.swift
//  OpenPane
//

import CoreGraphics

nonisolated enum WorkspaceSplitLayout {
    static let minimumBrowserWidth: CGFloat =
        PaneSplitLayout.defaultMinimumPaneWidth * 2 + PaneSplitLayout.defaultDividerWidth
    static let defaultPreviewWidth: CGFloat = 320
    static let minimumPreviewWidth: CGFloat = 280
    static let maximumPreviewWidth: CGFloat = 520
    static let previewDividerWidth: CGFloat = 10

    nonisolated struct Resolved: Equatable {
        let showsPreview: Bool
        let browserWidth: CGFloat
        let dividerWidth: CGFloat
        let previewWidth: CGFloat
    }

    nonisolated static func resolved(
        totalWidth: CGFloat,
        wantsPreview: Bool,
        proposedPreviewWidth: CGFloat?,
        keepsDirtyEditorVisible: Bool
    ) -> Resolved {
        let safeTotalWidth = max(0, totalWidth)
        guard wantsPreview else {
            return Resolved(
                showsPreview: false,
                browserWidth: safeTotalWidth,
                dividerWidth: 0,
                previewWidth: 0
            )
        }

        let dividerWidth = min(previewDividerWidth, safeTotalWidth)
        let requiredWidth = minimumBrowserWidth + dividerWidth + minimumPreviewWidth
        guard safeTotalWidth >= requiredWidth || keepsDirtyEditorVisible else {
            return Resolved(
                showsPreview: false,
                browserWidth: safeTotalWidth,
                dividerWidth: 0,
                previewWidth: 0
            )
        }

        let previewWidth = clampedPreviewWidth(
            proposedPreviewWidth ?? defaultPreviewWidth,
            totalWidth: safeTotalWidth,
            keepsDirtyEditorVisible: keepsDirtyEditorVisible
        )
        return Resolved(
            showsPreview: true,
            browserWidth: max(0, safeTotalWidth - dividerWidth - previewWidth),
            dividerWidth: dividerWidth,
            previewWidth: previewWidth
        )
    }

    nonisolated static func clampedPreviewWidth(
        _ proposedWidth: CGFloat,
        totalWidth: CGFloat,
        keepsDirtyEditorVisible: Bool
    ) -> CGFloat {
        let safeTotalWidth = max(0, totalWidth)
        let dividerWidth = min(previewDividerWidth, safeTotalWidth)
        let availableWidth = max(0, safeTotalWidth - dividerWidth)
        guard availableWidth > 0 else {
            return 0
        }

        let maximumLeavingBrowserUsable = max(0, availableWidth - minimumBrowserWidth)
        if maximumLeavingBrowserUsable >= minimumPreviewWidth {
            let maximumWidth = min(maximumPreviewWidth, maximumLeavingBrowserUsable)
            return min(max(proposedWidth, minimumPreviewWidth), maximumWidth)
        }

        guard keepsDirtyEditorVisible else {
            return 0
        }

        // A dirty editor is never hidden. At very small widths the browser may
        // temporarily compress while the preview retains as much of its
        // minimum editing width as the window can provide.
        return min(minimumPreviewWidth, availableWidth)
    }
}
