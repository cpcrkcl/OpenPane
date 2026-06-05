//
//  MainWindowView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct MainWindowView: View {
    @StateObject private var filePaneViewModel = FilePaneViewModel()

    var body: some View {
        FilePaneView(viewModel: filePaneViewModel)
        .frame(minWidth: 900, minHeight: 560)
    }
}
