//
//  SidebarViewModelTests.swift
//  OpenPaneTests
//
//  Created by Christopher Rego on 6/6/26.
//

import Foundation
import Testing
@testable import OpenPane

@MainActor
struct SidebarViewModelTests {
    @Test func defaultFavoritesIncludeStandardLocations() {
        let viewModel = SidebarViewModel()

        #expect(viewModel.favoriteLocations.map(\.name) == [
            "Home",
            "Desktop",
            "Documents",
            "Downloads",
            "Applications"
        ])
    }

    @Test func acceptsInjectedFavoriteLocations() {
        let favoriteLocation = FavoriteLocation(
            name: "Projects",
            url: URL(filePath: "/Projects", directoryHint: .isDirectory),
            systemImage: "folder"
        )

        let viewModel = SidebarViewModel(favoriteLocations: [favoriteLocation])

        #expect(viewModel.favoriteLocations == [favoriteLocation])
    }
}
