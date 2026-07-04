//
//  CommandPaletteViewModelTests.swift
//  OpenPaneTests
//
//  Created by Codex on 7/3/26.
//

import Testing
@testable import OpenPane

@MainActor
struct CommandPaletteViewModelTests {
    @Test func filteringReturnsMatchingCommands() {
        let viewModel = CommandPaletteViewModel(commands: [
            CommandPaletteCommand(id: "new-folder", title: "New Folder", systemImage: "folder") {},
            CommandPaletteCommand(id: "refresh", title: "Refresh Active Pane", systemImage: "arrow.clockwise") {},
            CommandPaletteCommand(id: "rename", title: "Rename", systemImage: "pencil") {}
        ])

        viewModel.query = "ref"

        #expect(viewModel.filteredCommands.map(\.id) == ["refresh"])
    }

    @Test func disabledCommandDoesNotRun() {
        var didRun = false
        let viewModel = CommandPaletteViewModel(commands: [
            CommandPaletteCommand(
                id: "rename",
                title: "Rename",
                systemImage: "pencil",
                disabledReason: "Select one item"
            ) {
                didRun = true
            }
        ])

        viewModel.runSelectedCommand()

        #expect(!didRun)
    }

    @Test func runningSelectedCommandCallsExpectedAction() {
        var ranCommandIDs: [String] = []
        let viewModel = CommandPaletteViewModel(commands: [
            CommandPaletteCommand(id: "first", title: "First", systemImage: "1.circle") {
                ranCommandIDs.append("first")
            },
            CommandPaletteCommand(id: "second", title: "Second", systemImage: "2.circle") {
                ranCommandIDs.append("second")
            }
        ])

        viewModel.moveSelectionDown()
        viewModel.runSelectedCommand()

        #expect(ranCommandIDs == ["second"])
    }
}
