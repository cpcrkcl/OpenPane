//
//  SidebarView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/6/26.
//

import AppKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: SidebarViewModel
    let activeLocation: PaneLocation
    let onSelect: (FavoriteLocation) -> Void
    let onSelectVolume: (MountedVolume) -> Void
    let onSelectNetwork: () -> Void
    let onManageVolumes: () -> Void

    @State private var favoriteToRename: FavoriteLocation?
    @State private var renameFavoriteName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarSectionTitle("Locations")
                .padding(.top, 14)

            SidebarNetworkRow(
                isActive: activeLocation == .network,
                onSelect: onSelectNetwork
            )

            sidebarSectionTitle("Favorites")
                .padding(.top, 10)

            List {
                ForEach(viewModel.favoriteLocations) { location in
                    SidebarFavoriteRow(
                        location: location,
                        isActive: activeLocation.fileURL?.standardizedFileURL == location.url.standardizedFileURL
                    ) {
                        onSelect(location)
                    }
                    .contextMenu {
                        Button("Rename") {
                            favoriteToRename = location
                            renameFavoriteName = location.name
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.url.path)
                        }
                        .disabled(!FileManager.default.fileExists(atPath: location.url.path))
                        Divider()
                        Button("Remove", role: .destructive) {
                            viewModel.removeFavorite(id: location.id)
                        }
                    }
                }
                .onMove { source, destination in
                    viewModel.reorderFavorites(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(
                height: min(
                    max(CGFloat(viewModel.favoriteLocations.count) * 36, 36),
                    240
                )
            )

            if !viewModel.allMountedVolumes.isEmpty {
                sidebarSectionHeader("Volumes", action: onManageVolumes)
                    .padding(.top, 10)

                ForEach(viewModel.visibleMountedVolumes) { volume in
                    SidebarVolumeRow(
                        volume: volume,
                        isActive: activeLocation.fileURL?.standardizedFileURL == volume.url.standardizedFileURL,
                        onHide: {
                            viewModel.hideVolume(volume)
                        }
                    ) {
                        onSelectVolume(volume)
                    }
                }

                if viewModel.visibleMountedVolumes.isEmpty {
                    Text("No visible volumes")
                        .font(.system(size: 11))
                        .foregroundStyle(CatppuccinMochaTheme.mutedText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("sidebar-no-visible-volumes")
                }
            }

            Spacer()
        }
        .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)
        .background(CatppuccinMochaTheme.sidebarBackground)
        .sheet(item: $favoriteToRename) { location in
            favoriteRenameSheet(favoriteID: location.id)
        }
    }

    private func favoriteRenameSheet(favoriteID: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Favorite")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)

            TextField("Name", text: $renameFavoriteName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    CatppuccinMochaTheme.mantle,
                    in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                )
                .onSubmit {
                    saveFavoriteRename(id: favoriteID)
                }
                .accessibilityIdentifier("rename-favorite-name")

            HStack {
                Button("Cancel") {
                    favoriteToRename = nil
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveFavoriteRename(id: favoriteID)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(renameFavoriteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(CatppuccinMochaTheme.appBackground)
        .preferredColorScheme(.dark)
    }

    private func saveFavoriteRename(id: String) {
        guard !renameFavoriteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        viewModel.renameFavorite(id: id, to: renameFavoriteName)
        favoriteToRename = nil
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(CatppuccinMochaTheme.mutedText)
            .padding(.horizontal, 14)
    }

    private func sidebarSectionHeader(_ title: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            sidebarSectionTitle(title)

            Spacer(minLength: 0)

            Button(action: action) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CatppuccinMochaTheme.mutedText)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .help("Manage Volumes")
            .accessibilityLabel("Manage Volumes")
            .accessibilityIdentifier("manage-volumes-button")
        }
    }
}

private struct SidebarNetworkRow: View {
    let isActive: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: "network")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CatppuccinMochaTheme.teal)
                    .frame(width: 18)

                Text("Network")
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? CatppuccinMochaTheme.primaryText : CatppuccinMochaTheme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive
                    ? CatppuccinMochaTheme.surface1.opacity(0.72)
                    : isHovered
                        ? CatppuccinMochaTheme.surface0.opacity(0.8)
                        : Color.clear,
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
                    .stroke(
                        isActive ? CatppuccinMochaTheme.teal.opacity(0.35) : Color.clear,
                        lineWidth: CatppuccinMochaTheme.hairlineBorderWidth
                    )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("sidebar-network")
    }
}

private struct SidebarFavoriteRow: View {
    let location: FavoriteLocation
    let isActive: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    private var iconColor: Color {
        switch location.name {
        case "Home":
            CatppuccinMochaTheme.lavender
        case "Desktop":
            CatppuccinMochaTheme.blue
        case "Documents":
            CatppuccinMochaTheme.sky
        case "Downloads":
            CatppuccinMochaTheme.mauve
        case "Applications":
            CatppuccinMochaTheme.teal
        default:
            CatppuccinMochaTheme.accent
        }
    }

    private var backgroundColor: Color {
        if isActive {
            return CatppuccinMochaTheme.surface1.opacity(0.72)
        }

        if isHovered {
            return CatppuccinMochaTheme.surface0.opacity(0.8)
        }

        return Color.clear
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: location.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

                Text(location.name)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? CatppuccinMochaTheme.primaryText : CatppuccinMochaTheme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
                    .stroke(
                        isActive ? iconColor.opacity(0.35) : Color.clear,
                        lineWidth: CatppuccinMochaTheme.hairlineBorderWidth
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
        .help(location.url.path)
        .accessibilityLabel("\(location.name), \(location.url.path)")
        .accessibilityIdentifier("sidebar-favorite-\(location.id)")
    }
}

private struct SidebarVolumeRow: View {
    let volume: MountedVolume
    let isActive: Bool
    let onHide: () -> Void
    let onSelect: () -> Void

    @State private var isHovered = false

    private var backgroundColor: Color {
        if isActive {
            return CatppuccinMochaTheme.surface1.opacity(0.72)
        }

        if isHovered {
            return CatppuccinMochaTheme.surface0.opacity(0.8)
        }

        return Color.clear
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                if let icon = volume.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: volume.isEjectable || volume.isRemovable ? "externaldrive" : "internaldrive")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CatppuccinMochaTheme.peach)
                        .frame(width: 18)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(volume.displayName)
                        .font(.system(size: 13, weight: isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? CatppuccinMochaTheme.primaryText : CatppuccinMochaTheme.secondaryText)
                        .lineLimit(1)

                    if let detailText = volume.detailText {
                        Text(detailText)
                            .font(.system(size: 10))
                            .foregroundStyle(CatppuccinMochaTheme.mutedText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
                    .stroke(
                        isActive ? CatppuccinMochaTheme.peach.opacity(0.35) : Color.clear,
                        lineWidth: CatppuccinMochaTheme.hairlineBorderWidth
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Hide Volume", action: onHide)
        }
        .accessibilityIdentifier("sidebar-volume-\(volume.displayName)")
    }
}
