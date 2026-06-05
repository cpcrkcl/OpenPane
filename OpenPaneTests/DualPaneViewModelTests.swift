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

    @Test func copySelectionToOtherPaneShowsErrorWhenNothingIsSelected() async {
        let leftPane = FilePaneViewModel(currentURL: URL(filePath: "/left"), fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: URL(filePath: "/right"), fileBrowserService: EmptyFileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)

        await viewModel.copySelectionToOtherPane()

        #expect(viewModel.errorMessage == "Select one or more items to copy.")
    }

    @Test func copySelectionToOtherPaneCopiesToInactivePaneAndRefreshesIt() async throws {
        let temporaryDirectory = try DualPaneTestTemporaryDirectory()
        let sourceItem = try temporaryDirectory.createSourceFile(named: "copy.txt", contents: "hello")
        let leftPane = FilePaneViewModel(currentURL: temporaryDirectory.sourceURL, fileBrowserService: EmptyFileBrowserService())
        let rightPane = FilePaneViewModel(currentURL: temporaryDirectory.destinationURL, fileBrowserService: FileBrowserService())
        let viewModel = DualPaneViewModel(leftPane: leftPane, rightPane: rightPane)
        leftPane.selectedItems = [sourceItem]

        await viewModel.copySelectionToOtherPane()

        let copiedURL = temporaryDirectory.destinationURL.appendingPathComponent("copy.txt")
        let copiedContents = try String(contentsOf: copiedURL, encoding: .utf8)
        #expect(copiedContents == "hello")
        #expect(rightPane.items.map(\.name) == ["copy.txt"])
        #expect(leftPane.selectedItems == [sourceItem])
        #expect(viewModel.errorMessage == nil)
    }
}

nonisolated private struct EmptyFileBrowserService: FileBrowserServicing {
    nonisolated func contentsOfDirectory(at url: URL, includeHiddenFiles: Bool) async throws -> [FileItem] {
        []
    }
}

private struct DualPaneTestTemporaryDirectory {
    let rootURL: URL
    let sourceURL: URL
    let destinationURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneDualPaneTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceURL = rootURL.appendingPathComponent("Source", isDirectory: true)
        destinationURL = rootURL.appendingPathComponent("Destination", isDirectory: true)

        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    }

    func createSourceFile(named name: String, contents: String) throws -> FileItem {
        let fileURL = sourceURL.appendingPathComponent(name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileItem(url: fileURL)
    }
}
