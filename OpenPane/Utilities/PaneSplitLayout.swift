//
//  PaneSplitLayout.swift
//  OpenPane
//
//  Created by Codex on 6/30/26.
//

import CoreGraphics

nonisolated enum PaneSplitLayout {
    static let defaultMinimumPaneWidth: CGFloat = 320
    static let defaultDividerWidth: CGFloat = 10

    nonisolated struct Resolved: Equatable {
        let leftWidth: CGFloat
        let dividerWidth: CGFloat
        let rightWidth: CGFloat
    }

    nonisolated static func resolved(
        totalWidth: CGFloat,
        proposedLeftWidth: CGFloat?,
        minimumPaneWidth: CGFloat = defaultMinimumPaneWidth,
        dividerWidth: CGFloat = defaultDividerWidth
    ) -> Resolved {
        let safeTotalWidth = max(0, totalWidth)
        let safeDividerWidth = min(max(0, dividerWidth), safeTotalWidth)
        let availablePaneWidth = max(0, safeTotalWidth - safeDividerWidth)
        let defaultLeftWidth = availablePaneWidth / 2
        let leftWidth = clampedLeftWidth(
            proposedLeftWidth ?? defaultLeftWidth,
            totalWidth: safeTotalWidth,
            minimumPaneWidth: minimumPaneWidth,
            dividerWidth: safeDividerWidth
        )

        return Resolved(
            leftWidth: leftWidth,
            dividerWidth: safeDividerWidth,
            rightWidth: max(0, availablePaneWidth - leftWidth)
        )
    }

    nonisolated static func clampedLeftWidth(
        _ proposedLeftWidth: CGFloat,
        totalWidth: CGFloat,
        minimumPaneWidth: CGFloat = defaultMinimumPaneWidth,
        dividerWidth: CGFloat = defaultDividerWidth
    ) -> CGFloat {
        let safeTotalWidth = max(0, totalWidth)
        let safeDividerWidth = min(max(0, dividerWidth), safeTotalWidth)
        let availablePaneWidth = max(0, safeTotalWidth - safeDividerWidth)
        let minimumWidth = effectiveMinimumPaneWidth(
            totalWidth: safeTotalWidth,
            minimumPaneWidth: minimumPaneWidth,
            dividerWidth: safeDividerWidth
        )
        let maximumLeftWidth = max(minimumWidth, availablePaneWidth - minimumWidth)

        return min(max(proposedLeftWidth, minimumWidth), maximumLeftWidth)
    }

    nonisolated static func effectiveMinimumPaneWidth(
        totalWidth: CGFloat,
        minimumPaneWidth: CGFloat = defaultMinimumPaneWidth,
        dividerWidth: CGFloat = defaultDividerWidth
    ) -> CGFloat {
        let safeTotalWidth = max(0, totalWidth)
        let safeDividerWidth = min(max(0, dividerWidth), safeTotalWidth)
        let availablePaneWidth = max(0, safeTotalWidth - safeDividerWidth)

        guard availablePaneWidth > 0 else {
            return 0
        }

        return min(max(0, minimumPaneWidth), availablePaneWidth / 2)
    }
}
