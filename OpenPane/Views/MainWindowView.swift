//
//  MainWindowView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct MainWindowView: View {
    @StateObject private var dualPaneViewModel = DualPaneViewModel()

    var body: some View {
        DualPaneView(viewModel: dualPaneViewModel)
            .frame(minWidth: 1100, minHeight: 620)
    }
}
