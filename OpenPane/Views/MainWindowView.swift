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
        HStack(spacing: 0) {
            SidebarView(viewModel: sidebarViewModel) { location in
                Task {
                    await dualPaneViewModel.activePane.setDirectory(location.url)
                }
            }

            Divider()

            DualPaneView(viewModel: dualPaneViewModel)
        }
            .frame(minWidth: 1100, minHeight: 620)
    }
}
