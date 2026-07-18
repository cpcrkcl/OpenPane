//
//  MainWindowView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import Combine
import SwiftUI

nonisolated enum MainWindowLayout {
    static let minimumWindowWidth: CGFloat = 640
    static let minimumWindowHeight: CGFloat = 500
    static let inlineSidebarMinimumWidth: CGFloat = 1_160
    static let inlineSidebarWithPreviewMinimumWidth: CGFloat = 1_460
    static let compactSpacingMaximumWidth: CGFloat = 800

    nonisolated struct Resolved: Equatable {
        let showsInlineSidebar: Bool
        let outerPadding: CGFloat
        let surfaceSpacing: CGFloat
    }

    nonisolated static func resolved(totalWidth: CGFloat, wantsPreview: Bool) -> Resolved {
        let safeWidth = max(0, totalWidth)
        let sidebarMinimumWidth = wantsPreview
            ? inlineSidebarWithPreviewMinimumWidth
            : inlineSidebarMinimumWidth
        let usesCompactSpacing = safeWidth < compactSpacingMaximumWidth

        return Resolved(
            showsInlineSidebar: safeWidth >= sidebarMinimumWidth,
            outerPadding: usesCompactSpacing ? 8 : 14,
            surfaceSpacing: usesCompactSpacing ? 8 : 12
        )
    }
}

struct MainWindowView: View {
    @StateObject private var sidebarViewModel: SidebarViewModel
    @ObservedObject private var volumeVisibilityStore: VolumeVisibilityStore
    @StateObject private var dualPaneViewModel: DualPaneViewModel
    @StateObject private var sessionAutosaveController: SessionAutosaveController
    @StateObject private var recentLocationStore = RecentLocationStore()
    @State private var isShowingVolumeVisibilityPicker = false
    @State private var isShowingCompactSidebar = false
    @AppStorage(PaneLinkMode.userDefaultsKey) private var paneLinkModeRawValue = PaneLinkMode.off.rawValue
    private let isSessionPersistenceEnabled: Bool

    init(
        sessionPersistenceService: (any SessionPersistenceServicing)? = nil,
        volumeVisibilityStore: VolumeVisibilityStore? = nil,
        favoriteStore: FavoriteStore? = nil
    ) {
        let resolvedVolumeVisibilityStore = volumeVisibilityStore ?? VolumeVisibilityStore()
        let resolvedFavoriteStore = favoriteStore ?? FavoriteStore()
        _volumeVisibilityStore = ObservedObject(wrappedValue: resolvedVolumeVisibilityStore)
        _sidebarViewModel = StateObject(
            wrappedValue: SidebarViewModel(
                volumeVisibilityStore: resolvedVolumeVisibilityStore,
                favoriteStore: resolvedFavoriteStore
            )
        )
        let resolvedSessionPersistenceService = sessionPersistenceService ?? UserDefaultsSessionPersistenceService()
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let isRunningUnderXCTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let restoredViewModel = DualPaneViewModel.restoring(
            isUITesting || isRunningUnderXCTest ? nil : resolvedSessionPersistenceService.loadSession()
        )
        restoredViewModel.setPaneLinkMode(
            PaneLinkMode(rawValue: UserDefaults.standard.string(forKey: PaneLinkMode.userDefaultsKey) ?? "") ?? .off
        )
        _dualPaneViewModel = StateObject(wrappedValue: restoredViewModel)
        _sessionAutosaveController = StateObject(
            wrappedValue: SessionAutosaveController(service: resolvedSessionPersistenceService)
        )
        self.isSessionPersistenceEnabled = !isUITesting && !isRunningUnderXCTest
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = MainWindowLayout.resolved(
                totalWidth: geometry.size.width,
                wantsPreview: dualPaneViewModel.isPreviewPanelVisible
            )

            VStack(spacing: layout.surfaceSpacing) {
                header(
                    showsInlineSidebar: layout.showsInlineSidebar,
                    compactSidebarHeight: max(320, min(520, geometry.size.height - 120))
                )

                HStack(spacing: layout.surfaceSpacing) {
                    if layout.showsInlineSidebar {
                        sidebarSurface()

                        sidebarDivider
                    }

                    mainContentSurface
                        .layoutPriority(1)
                }
            }
            .padding(layout.outerPadding)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onChange(of: layout.showsInlineSidebar) { _, showsInlineSidebar in
                if showsInlineSidebar {
                    isShowingCompactSidebar = false
                }
            }
        }
        .background(CatppuccinMochaTheme.appBackground)
        .background {
            MouseNavigationEventView {
                Task {
                    await dualPaneViewModel.goBackInActivePane()
                }
            } onForward: {
                Task {
                    await dualPaneViewModel.goForwardInActivePane()
                }
            }
            .frame(width: 0, height: 0)
        }
        .preferredColorScheme(.dark)
        .frame(
            minWidth: MainWindowLayout.minimumWindowWidth,
            minHeight: MainWindowLayout.minimumWindowHeight
        )
        .onReceive(dualPaneViewModel.sessionStateDidChange) { _ in
            guard isSessionPersistenceEnabled else {
                return
            }

            Task { @MainActor in
                await Task.yield()
                sessionAutosaveController.scheduleSave(dualPaneViewModel.sessionState())
            }
        }
        .onChange(of: paneLinkModeRawValue) { _, rawValue in
            dualPaneViewModel.setPaneLinkMode(PaneLinkMode(rawValue: rawValue) ?? .off)
        }
        .onReceive(dualPaneViewModel.$paneLinkMode.dropFirst()) { mode in
            guard paneLinkModeRawValue != mode.rawValue else {
                return
            }
            paneLinkModeRawValue = mode.rawValue
        }
        .onDisappear {
            guard isSessionPersistenceEnabled else {
                return
            }

            sessionAutosaveController.saveImmediately(dualPaneViewModel.sessionState())
        }
        .sheet(isPresented: $isShowingVolumeVisibilityPicker) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Visible Volumes")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CatppuccinMochaTheme.primaryText)

                    Spacer()

                    Button("Done") {
                        isShowingVolumeVisibilityPicker = false
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }

                Text("Choose which mounted volumes appear in the sidebar. New volumes are shown automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)

                VolumeVisibilityPickerView(
                    visibilityStore: volumeVisibilityStore,
                    volumes: sidebarViewModel.allMountedVolumes
                )
            }
            .padding(18)
            .frame(width: 360, height: 360)
            .background(CatppuccinMochaTheme.appBackground)
            .preferredColorScheme(.dark)
        }
    }

    private func header(
        showsInlineSidebar: Bool,
        compactSidebarHeight: CGFloat
    ) -> some View {
        HStack(spacing: 12) {
            if !showsInlineSidebar {
                Button {
                    isShowingCompactSidebar.toggle()
                } label: {
                    Label("Locations", systemImage: "sidebar.left")
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .help("Show Locations")
                .accessibilityIdentifier("sidebar-toggle-button")
            }

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
        .popover(isPresented: $isShowingCompactSidebar, arrowEdge: .top) {
            sidebarSurface(closesAfterSelection: true)
                .frame(width: 220, height: compactSidebarHeight)
                .padding(8)
                .background(CatppuccinMochaTheme.appBackground)
                .preferredColorScheme(.dark)
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

    private func sidebarSurface(closesAfterSelection: Bool = false) -> some View {
        SidebarView(
            viewModel: sidebarViewModel,
            activeLocation: dualPaneViewModel.activePane.currentLocation
        ) { location in
            if closesAfterSelection {
                isShowingCompactSidebar = false
            }
            Task {
                await dualPaneViewModel.navigateActivePane(to: location.url)
            }
        } onSelectVolume: { volume in
            if closesAfterSelection {
                isShowingCompactSidebar = false
            }
            Task {
                await dualPaneViewModel.navigateActivePane(to: volume.url)
            }
        } onSelectNetwork: {
            if closesAfterSelection {
                isShowingCompactSidebar = false
            }
            Task {
                await dualPaneViewModel.navigateActivePane(to: .network)
            }
        } onManageVolumes: {
            isShowingVolumeVisibilityPicker = true
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
        DualPaneView(
            viewModel: dualPaneViewModel,
            sidebarViewModel: sidebarViewModel,
            recentLocationStore: recentLocationStore,
            onMountNetworkURLs: { paneSide, urls in
                Task {
                    if let url = urls.first {
                        await dualPaneViewModel.pane(for: paneSide).navigate(to: .file(url))
                    }
                    sidebarViewModel.refreshVolumes()
                }
            }
        )
            .background(CatppuccinMochaTheme.windowBackground)
            .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge))
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusLarge)
                    .stroke(CatppuccinMochaTheme.surface1, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("main-content-surface")
    }
}
