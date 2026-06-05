//
//  MainWindowView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct MainWindowView: View {
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            mainContent
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sidebar")
                .font(.headline)
            Text("Local locations will appear here.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mainContent: some View {
        Text("OpenPane")
            .font(.largeTitle)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
