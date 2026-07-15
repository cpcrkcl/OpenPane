//
//  RecentLocationStore.swift
//  OpenPane
//
//  Created by Codex on 7/12/26.
//

import Combine
import Foundation

@MainActor
final class RecentLocationStore: ObservableObject {
    nonisolated static let defaultUserDefaultsKey = "OpenPaneRecentLocations"
    nonisolated static let defaultMaximumCount = 12

    private let userDefaults: UserDefaults
    private let key: String
    private let maximumCount: Int

    @Published private(set) var recentPaths: [String]

    init(
        userDefaults: UserDefaults = .standard,
        key: String = RecentLocationStore.defaultUserDefaultsKey,
        maximumCount: Int = RecentLocationStore.defaultMaximumCount
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.maximumCount = max(1, maximumCount)
        let storedPaths = userDefaults.stringArray(forKey: key) ?? []
        let sanitizedPaths = Self.sanitized(storedPaths, maximumCount: self.maximumCount)
        self.recentPaths = sanitizedPaths

        if sanitizedPaths != storedPaths {
            if sanitizedPaths.isEmpty {
                userDefaults.removeObject(forKey: key)
            } else {
                userDefaults.set(sanitizedPaths, forKey: key)
            }
        } else if userDefaults.object(forKey: key) != nil,
                  userDefaults.stringArray(forKey: key) == nil {
            userDefaults.removeObject(forKey: key)
        }
    }

    func record(_ url: URL) {
        guard url.isFileURL else {
            return
        }

        let path = url.standardizedFileURL.path
        var paths = recentPaths.filter { $0 != path }
        paths.insert(path, at: 0)

        if paths.count > maximumCount {
            paths = Array(paths.prefix(maximumCount))
        }

        setRecentPaths(paths)
    }

    func remove(path: String) {
        let normalizedPath = Self.normalizedAbsolutePath(path) ?? path
        let paths = recentPaths.filter { $0 != normalizedPath }
        setRecentPaths(paths)
    }

    func clear() {
        recentPaths = []
        userDefaults.removeObject(forKey: key)
    }

    private func setRecentPaths(_ paths: [String]) {
        guard paths != recentPaths else {
            return
        }
        recentPaths = paths
        userDefaults.set(paths, forKey: key)
    }

    private static func sanitized(_ paths: [String], maximumCount: Int) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for path in paths {
            guard let normalizedPath = normalizedAbsolutePath(path),
                  seen.insert(normalizedPath).inserted else {
                continue
            }

            result.append(normalizedPath)
            if result.count == maximumCount {
                break
            }
        }

        return result
    }

    private static func normalizedAbsolutePath(_ path: String) -> String? {
        guard !path.isEmpty, path.hasPrefix("/") else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }
}
