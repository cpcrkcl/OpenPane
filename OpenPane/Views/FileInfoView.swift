//
//  FileInfoView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/8/26.
//

import AppKit
import SwiftUI

struct FileInfoView: View {
    let item: FileItem
    let onCopyPath: () -> Void
    let onRevealInFinder: () -> Void
    let onClose: () -> Void

    @State private var details: FileInfoDetails?
    @State private var icon: NSImage?

    private let fileIconService = FileIconService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(spacing: 10) {
                infoRow(title: "Name", value: item.displayName)
                infoRow(title: "Path", value: item.url.path, canSelect: true)
                infoRow(title: "Kind", value: item.kindDescription)
                infoRow(title: "Size", value: item.isDirectory ? "--" : item.formattedSize)
                infoRow(title: "Modified", value: item.formattedModifiedDateOrPlaceholder)
                infoRow(title: "Created", value: details?.formattedCreatedDate ?? "--")
                infoRow(title: "Permissions", value: details?.permissionsDescription ?? "--")
                infoRow(title: "Hidden", value: item.isHidden ? "Yes" : "No")
            }

            actions
        }
        .padding(22)
        .frame(width: 520)
        .background(CatppuccinMochaTheme.mantle)
        .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
        .task(id: item.id) {
            details = await FileInfoDetails.load(for: item.url)
        }
        .task(id: item.id) {
            let loadedIcon = await fileIconService.icon(for: item)
            guard !Task.isCancelled else {
                return
            }
            icon = loadedIcon
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(
                            item.isDirectory ? CatppuccinMochaTheme.lavender : CatppuccinMochaTheme.mutedText
                        )
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Get Info")
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(CatppuccinMochaTheme.mutedText)

                Text(item.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }

    private func infoRow(title: String, value: String, canSelect: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CatppuccinMochaTheme.mutedText)
                .frame(width: 92, alignment: .trailing)

            infoValueText(value.isEmpty ? "--" : value, lineLimit: title == "Path" ? 3 : 2, canSelect: canSelect)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func infoValueText(_ value: String, lineLimit: Int, canSelect: Bool) -> some View {
        if canSelect {
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)
                .lineLimit(lineLimit)
                .textSelection(.enabled)
        } else {
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)
                .lineLimit(lineLimit)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                onCopyPath()
            } label: {
                Label("Copy Path", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(SecondaryActionButtonStyle())

            Button {
                onRevealInFinder()
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }
            .buttonStyle(SecondaryActionButtonStyle())

            Spacer()

            Button("Close") {
                onClose()
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .keyboardShortcut(.cancelAction)
        }
        .padding(.top, 4)
    }
}

private struct FileInfoDetails: Sendable {
    let createdDate: Date?
    let posixPermissions: Int?

    var formattedCreatedDate: String {
        guard let createdDate else {
            return "--"
        }

        return createdDate.formatted(date: .abbreviated, time: .shortened)
    }

    var permissionsDescription: String {
        guard let posixPermissions else {
            return "--"
        }

        let octal = String(posixPermissions, radix: 8)
        return "\(Self.symbolicPermissions(for: posixPermissions)) (\(octal))"
    }

    static func load(for url: URL) async -> FileInfoDetails {
        await Task.detached(priority: .userInitiated) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)

            return FileInfoDetails(
                createdDate: attributes?[.creationDate] as? Date,
                posixPermissions: attributes?[.posixPermissions] as? Int
            )
        }.value
    }

    private static func symbolicPermissions(for permissions: Int) -> String {
        let masksAndCharacters: [(Int, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]

        return String(masksAndCharacters.map { mask, character in
            permissions & mask == mask ? character : "-"
        })
    }
}

private extension FileItem {
    var formattedModifiedDateOrPlaceholder: String {
        formattedModifiedDate.isEmpty ? "--" : formattedModifiedDate
    }
}
