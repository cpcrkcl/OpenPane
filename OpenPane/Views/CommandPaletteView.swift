//
//  CommandPaletteView.swift
//  OpenPane
//
//  Created by Codex on 7/3/26.
//

import SwiftUI

struct CommandPaletteView: View {
    let commands: [CommandPaletteCommand]
    @Binding var isPresented: Bool

    @StateObject private var viewModel = CommandPaletteViewModel()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .foregroundStyle(CatppuccinMochaTheme.accent)

                TextField("Search commands", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)
                    .focused($isSearchFocused)
                    .onSubmit(runSelectedCommand)
                    .accessibilityIdentifier("command-palette-search-field")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(CatppuccinMochaTheme.surface0.opacity(0.9))

            Divider()
                .overlay(CatppuccinMochaTheme.surface1)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(viewModel.filteredCommands.enumerated()), id: \.element.id) { index, command in
                        commandRow(command, isSelected: index == viewModel.selectedIndex)
                            .onTapGesture {
                                viewModel.selectedIndex = index
                                runSelectedCommand()
                            }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 520)
        .background(
            CatppuccinMochaTheme.windowBackground,
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                .stroke(CatppuccinMochaTheme.accent.opacity(0.36), lineWidth: CatppuccinMochaTheme.paneBorderWidth)
        }
        .shadow(color: .black.opacity(0.35), radius: 28, y: 18)
        .accessibilityIdentifier("command-palette")
        .onAppear {
            viewModel.updateCommands(commands)
            isSearchFocused = true
        }
        .onChange(of: commandPresentationSignature) { _, _ in
            viewModel.updateCommands(commands)
        }
        .onExitCommand {
            isPresented = false
        }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                viewModel.moveSelectionDown()
            case .up:
                viewModel.moveSelectionUp()
            default:
                break
            }
        }
    }

    private var commandPresentationSignature: [String] {
        commands.map { command in
            [command.id, command.title, command.systemImage, command.disabledReason ?? ""]
                .joined(separator: "\u{0}")
        }
    }

    private func commandRow(_ command: CommandPaletteCommand, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(command.isEnabled ? CatppuccinMochaTheme.accent : CatppuccinMochaTheme.mutedText)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(command.isEnabled ? CatppuccinMochaTheme.primaryText : CatppuccinMochaTheme.mutedText)

                if let disabledReason = command.disabledReason {
                    Text(disabledReason)
                        .font(.system(size: 10))
                        .foregroundStyle(CatppuccinMochaTheme.mutedText)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isSelected ? CatppuccinMochaTheme.surface1.opacity(0.72) : Color.clear,
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
        )
        .opacity(command.isEnabled ? 1 : 0.64)
        .accessibilityIdentifier("command-palette-row-\(command.id)")
    }

    private func runSelectedCommand() {
        let beforeRun = isPresented
        viewModel.runSelectedCommand()

        if beforeRun,
           viewModel.filteredCommands.indices.contains(viewModel.selectedIndex),
           viewModel.filteredCommands[viewModel.selectedIndex].isEnabled {
            isPresented = false
        }
    }
}
