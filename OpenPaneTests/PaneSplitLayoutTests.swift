//
//  PaneSplitLayoutTests.swift
//  OpenPaneTests
//
//  Created by Codex on 6/30/26.
//

import CoreGraphics
import Testing
@testable import OpenPane

struct PaneSplitLayoutTests {
    @Test func defaultLayoutSplitsAvailableWidthAroundDivider() {
        let layout = PaneSplitLayout.resolved(
            totalWidth: 810,
            proposedLeftWidth: nil,
            minimumPaneWidth: 320,
            dividerWidth: 10
        )

        #expect(layout.leftWidth == 400)
        #expect(layout.dividerWidth == 10)
        #expect(layout.rightWidth == 400)
    }

    @Test func leftPaneWidthClampsToMinimumWidth() {
        let layout = PaneSplitLayout.resolved(
            totalWidth: 900,
            proposedLeftWidth: 120,
            minimumPaneWidth: 320,
            dividerWidth: 10
        )

        #expect(layout.leftWidth == 320)
        #expect(layout.rightWidth == 570)
    }

    @Test func rightPaneWidthClampsToMinimumWidth() {
        let layout = PaneSplitLayout.resolved(
            totalWidth: 900,
            proposedLeftWidth: 820,
            minimumPaneWidth: 320,
            dividerWidth: 10
        )

        #expect(layout.leftWidth == 570)
        #expect(layout.rightWidth == 320)
    }

    @Test func tinyTotalWidthNeverProducesNegativePaneWidths() {
        let layout = PaneSplitLayout.resolved(
            totalWidth: 90,
            proposedLeftWidth: 1_000,
            minimumPaneWidth: 320,
            dividerWidth: 10
        )

        #expect(layout.leftWidth >= 0)
        #expect(layout.rightWidth >= 0)
        #expect(layout.leftWidth + layout.dividerWidth + layout.rightWidth == 90)
    }

    @Test func effectiveMinimumShrinksWhenContainerCannotFitBothMinimums() {
        let minimumWidth = PaneSplitLayout.effectiveMinimumPaneWidth(
            totalWidth: 410,
            minimumPaneWidth: 320,
            dividerWidth: 10
        )

        #expect(minimumWidth == 200)
    }

    @Test func persistedSplitFractionRestoresToClampedPaneWidth() {
        let totalWidth: CGFloat = 900
        let restoredLeftWidth = PaneSplitLayout.clampedLeftWidth(
            totalWidth * 0.8,
            totalWidth: totalWidth,
            minimumPaneWidth: 320,
            dividerWidth: 10
        )

        #expect(restoredLeftWidth == 570)
    }
}
