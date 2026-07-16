//
//  WorkspaceSplitLayoutTests.swift
//  OpenPaneTests
//

import CoreGraphics
import Testing
@testable import OpenPane

struct WorkspaceSplitLayoutTests {
    @Test func visiblePreviewLeavesBrowserUsable() {
        let layout = WorkspaceSplitLayout.resolved(
            totalWidth: 1_100,
            wantsPreview: true,
            proposedPreviewWidth: 320,
            keepsDirtyEditorVisible: false
        )

        #expect(layout.showsPreview)
        #expect(layout.previewWidth == 320)
        #expect(layout.browserWidth == 770)
    }

    @Test func cleanPreviewCollapsesBelowMinimumWorkspaceWidth() {
        let layout = WorkspaceSplitLayout.resolved(
            totalWidth: 900,
            wantsPreview: true,
            proposedPreviewWidth: 320,
            keepsDirtyEditorVisible: false
        )

        #expect(!layout.showsPreview)
        #expect(layout.browserWidth == 900)
        #expect(layout.previewWidth == 0)
    }

    @Test func dirtyPreviewStaysVisibleInNarrowWorkspace() {
        let layout = WorkspaceSplitLayout.resolved(
            totalWidth: 900,
            wantsPreview: true,
            proposedPreviewWidth: 320,
            keepsDirtyEditorVisible: true
        )

        #expect(layout.showsPreview)
        #expect(layout.previewWidth == 280)
        #expect(layout.browserWidth == 610)
    }

    @Test func previewWidthClampsToMaximumAndBrowserMinimum() {
        let layout = WorkspaceSplitLayout.resolved(
            totalWidth: 1_500,
            wantsPreview: true,
            proposedPreviewWidth: 900,
            keepsDirtyEditorVisible: false
        )

        #expect(layout.previewWidth == 520)
        #expect(layout.browserWidth == 970)
    }
}
