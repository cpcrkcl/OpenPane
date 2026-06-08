//
//  MainWindowView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct MainWindowView: View {
    @StateObject private var sidebarViewModel = SidebarViewModel()
    @StateObject private var dualPaneViewModel = DualPaneViewModel()

    var body: some View {
        VStack(spacing: 12) {
            header

            HStack(spacing: 12) {
                sidebarSurface

                sidebarDivider

                mainContentSurface
            }
        }
        .padding(14)
        .background(CatppuccinMochaTheme.appBackground)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1000, minHeight: 650)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("OpenPane")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)

            activePaneBadge

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            CatppuccinMochaTheme.windowBackground,
            in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium)
                .stroke(CatppuccinMochaTheme.surface0, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }

    private var activePaneBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(CatppuccinMochaTheme.accent)
                .frame(width: 6, height: 6)

            Text(dualPaneViewModel.activePaneSide == .left ? "Left pane active" : "Right pane active")
                .font(.caption)
                .foregroundStyle(CatppuccinMochaTheme.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            CatppuccinMochaTheme.paneBackgroundElevated,
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }

    private var sidebarSurface: some View {
        SidebarView(
            viewModel: sidebarViewModel,
            activeURL: dualPaneViewModel.activePane.currentURL
        ) { location in
            Task {
                await dualPaneViewModel.activePane.setDirectory(location.url)
            }
        }
        .background(CatppuccinMochaTheme.sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                .stroke(CatppuccinMochaTheme.surface0, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
        }
    }

    private var sidebarDivider: some View {
        Rectangle()
            .fill(CatppuccinMochaTheme.surface0.opacity(0.9))
            .frame(width: CatppuccinMochaTheme.hairlineBorderWidth)
            .padding(.vertical, 4)
    }

    private var mainContentSurface: some View {
        DualPaneView(viewModel: dualPaneViewModel)
            .background(CatppuccinMochaTheme.windowBackground)
            .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                    .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
            }
    }
}
