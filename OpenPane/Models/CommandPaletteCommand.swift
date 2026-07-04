//
//  CommandPaletteCommand.swift
//  OpenPane
//
//  Created by Codex on 7/3/26.
//

import Combine
import Foundation

@MainActor
struct CommandPaletteCommand: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let disabledReason: String?
    let action: @MainActor () -> Void

    var isEnabled: Bool {
        disabledReason == nil
    }

    init(
        id: String,
        title: String,
        systemImage: String,
        disabledReason: String? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.disabledReason = disabledReason
        self.action = action
    }
}

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var query: String
    @Published var selectedIndex: Int
    private(set) var commands: [CommandPaletteCommand]

    init(
        commands: [CommandPaletteCommand] = [],
        query: String = ""
    ) {
        self.commands = commands
        self.query = query
        self.selectedIndex = 0
    }

    var filteredCommands: [CommandPaletteCommand] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return commands
        }

        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    func updateCommands(_ commands: [CommandPaletteCommand]) {
        self.commands = commands
        clampSelection()
    }

    func moveSelectionDown() {
        guard !filteredCommands.isEmpty else {
            selectedIndex = 0
            return
        }

        selectedIndex = min(selectedIndex + 1, filteredCommands.count - 1)
    }

    func moveSelectionUp() {
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func runSelectedCommand() {
        let commands = filteredCommands

        guard commands.indices.contains(selectedIndex) else {
            return
        }

        let command = commands[selectedIndex]
        guard command.isEnabled else {
            return
        }

        command.action()
    }

    private func clampSelection() {
        if filteredCommands.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, filteredCommands.count - 1)
        }
    }
}
