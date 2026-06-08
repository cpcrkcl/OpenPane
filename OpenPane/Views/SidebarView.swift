//
//  SidebarView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/6/26.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: SidebarViewModel
    let activeURL: URL?
    let onSelect: (FavoriteLocation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorites")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(CatppuccinMochaTheme.mutedText)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            ForEach(viewModel.favoriteLocations) { location in
                SidebarFavoriteRow(
                    location: location,
                    isActive: activeURL == location.url
                ) {
                    onSelect(location)
                }
            }

            Spacer()
        }
        .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)
        .background(CatppuccinMochaTheme.sidebarBackground)
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
    }
}
