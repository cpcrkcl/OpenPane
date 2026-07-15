//
//  GoToFolderSheet.swift
//  OpenPane
//
//  Created by Codex on 7/12/26.
//

import SwiftUI

struct GoToFolderSheet: View {
    @Binding var pathText: String
    let recentPaths: [String]
    let errorMessage: String?
    let onSubmit: () -> Void
    let onSelectRecent: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isPathFieldFocused: Bool

    private var suggestedRecentPaths: [String] {
        let query = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query != "~" else {
            return recentPaths
        }

        let matches = recentPaths.filter {
            $0.localizedStandardContains(query)
        }
        return matches.isEmpty ? recentPaths : matches
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Go to Folder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)

                Text("Enter an absolute path or use ~ for your home folder.")
                    .font(.system(size: 12))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            }

            TextField("Path", text: $pathText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    CatppuccinMochaTheme.mantle,
                    in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                        .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
                }
                .focused($isPathFieldFocused)
                .onSubmit(onSubmit)
                .accessibilityIdentifier("go-to-folder-path")

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(CatppuccinMochaTheme.red)
                    .accessibilityIdentifier("go-to-folder-error")
            }

            if !suggestedRecentPaths.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CatppuccinMochaTheme.mutedText)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(suggestedRecentPaths, id: \.self) { path in
                                Button {
                                    pathText = path
                                    onSelectRecent(path)
                                } label: {
                                    Text(path)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(CatppuccinMochaTheme.secondaryText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .help("Go to \(path)")
                                .accessibilityLabel("Go to \(path)")
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(SecondaryActionButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Go", action: onSubmit)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(pathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("go-to-folder-submit")
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(CatppuccinMochaTheme.appBackground)
        .preferredColorScheme(.dark)
        .onAppear {
            isPathFieldFocused = true
        }
    }
}
