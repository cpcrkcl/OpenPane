//
//  SidebarView.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/6/26.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: SidebarViewModel
    let onSelect: (FavoriteLocation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Favorites")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ForEach(viewModel.favoriteLocations) { location in
                Button {
                    onSelect(location)
                } label: {
                    Label(location.name, systemImage: location.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }

            Spacer()
        }
        .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
