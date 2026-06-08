//
//  SidebarViewModel.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/6/26.
//

import Combine
import Foundation

@MainActor
final class SidebarViewModel: ObservableObject {
    @Published var favoriteLocations: [FavoriteLocation]

    init(favoriteLocations: [FavoriteLocation]? = nil) {
        self.favoriteLocations = favoriteLocations ?? Self.defaultFavoriteLocations()
    }

    private static func defaultFavoriteLocations(fileManager: FileManager = .default) -> [FavoriteLocation] {
        let homeURL = fileManager.homeDirectoryForCurrentUser

        return [
            FavoriteLocation(name: "Home", url: homeURL, systemImage: "house"),
            FavoriteLocation(
                name: "Desktop",
                url: standardDirectoryURL(.desktopDirectory, fileManager: fileManager) ?? homeURL.appendingPathComponent("Desktop", isDirectory: true),
                systemImage: "display"
            ),
            FavoriteLocation(
                name: "Documents",
                url: standardDirectoryURL(.documentDirectory, fileManager: fileManager) ?? homeURL.appendingPathComponent("Documents", isDirectory: true),
                systemImage: "doc.text"
            ),
            FavoriteLocation(
                name: "Downloads",
                url: standardDirectoryURL(.downloadsDirectory, fileManager: fileManager) ?? homeURL.appendingPathComponent("Downloads", isDirectory: true),
                systemImage: "arrow.down.circle"
            ),
            FavoriteLocation(
                name: "Applications",
                url: applicationsURL(fileManager: fileManager),
                systemImage: "square.grid.2x2"
            )
        ]
    }

    private static func standardDirectoryURL(_ directory: FileManager.SearchPathDirectory, fileManager: FileManager) -> URL? {
        fileManager.urls(for: directory, in: .userDomainMask).first
    }

    private static func applicationsURL(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first
            ?? fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first
            ?? URL(filePath: "/Applications", directoryHint: .isDirectory)
    }
}
