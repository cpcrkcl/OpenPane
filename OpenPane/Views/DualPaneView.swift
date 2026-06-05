//
//  DualPaneView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/4/26.
//

import SwiftUI

struct DualPaneView: View {
    @ObservedObject var viewModel: DualPaneViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(12)

            Divider()

            HSplitView {
                FilePaneView(
                    viewModel: viewModel.leftPane,
                    isActive: viewModel.activePaneSide == .left
                ) {
                    viewModel.setActivePane(.left)
                }
                .frame(minWidth: 320)

                FilePaneView(
                    viewModel: viewModel.rightPane,
                    isActive: viewModel.activePaneSide == .right
                ) {
                    viewModel.setActivePane(.right)
                }
                .frame(minWidth: 320)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await viewModel.refreshBoth()
                }
            } label: {
                Label("Refresh Both", systemImage: "arrow.clockwise")
            }

            Button {
                Task {
                    await viewModel.swapPaneLocations()
                }
            } label: {
                Label("Swap Panes", systemImage: "arrow.left.arrow.right")
            }

            Spacer()

            Text(viewModel.activePaneSide == .left ? "Left pane active" : "Right pane active")
                .foregroundStyle(.secondary)
        }
    }
}
