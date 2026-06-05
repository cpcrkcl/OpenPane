//
//  DualPaneViewModelTests.swift
//  OpenPaneTests
//
//  Created by Christopher Rego on 6/4/26.
//

import Foundation
import Testing
@testable import OpenPane

@MainActor
struct DualPaneViewModelTests {
    @Test func defaultsToLeftActivePane() {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        #expect(viewModel.activePaneSide == .left)
        #expect(viewModel.activePane === leftPane)
        #expect(viewModel.inactivePane === rightPane)
    }

    @Test func setActivePaneSwitchesActiveAndInactivePane() {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        viewModel.setActivePane(.right)

        #expect(viewModel.activePaneSide == .right)
        #expect(viewModel.activePane === rightPane)
        #expect(viewModel.inactivePane === leftPane)
    }

    @Test func swapPaneLocationsExchangesCurrentURLs() async {
        let leftURL = URL(filePath: "/left")
        let rightURL = URL(filePath: "/right")
        let leftPane = FilePaneViewModel(currentURL: leftURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: rightURL, fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.swapPaneLocations()

        #expect(viewModel.leftPane.currentURL == rightURL)
        #expect(viewModel.rightPane.currentURL == leftURL)
    }
}

nonisolated private struct EmptyFileBrowserService: FileBrowserServicing {
    nonisolated func contentsOfDirectory(at url: URL, includeHiddenFiles: Bool) async throws -> [FileItem] {
        []
    }
}
