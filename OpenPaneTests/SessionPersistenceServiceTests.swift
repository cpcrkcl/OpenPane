//
//  SessionPersistenceServiceTests.swift
//  OpenPaneTests
//
//  Created by Codex on 7/3/26.
//

import Foundation
import Testing
@testable import OpenPane

@MainActor
struct SessionPersistenceServiceTests {
    @Test func encodingAndDecodingSessionStatePreservesPaneAndTabData() throws {
        let state = sampleSessionState()
        let data = try JSONEncoder().encode(state)

        let decoded = try JSONDecoder().decode(SessionState.self, from: data)

        #expect(decoded == state)
    }

    @Test func restoringMissingFolderFallsBackToHomeDirectory() {
        let missingURL = URL(filePath: "/tmp/OpenPaneMissing-\(UUID().uuidString)", directoryHint: .isDirectory)
        var state = sampleSessionState()
        state.leftPane.tabs = [
            SessionTabState(id: UUID(), currentURL: missingURL)
        ]
        state.leftPane.activeTabID = state.leftPane.tabs[0].id
        state.leftPane.currentURL = missingURL
        let fallbackURL = URL(filePath: "/tmp", directoryHint: .isDirectory)

        let viewModel = DualPaneViewModel.restoring(state, fallbackURL: fallbackURL)

        #expect(viewModel.leftPane.currentURL == fallbackURL)
        #expect(viewModel.leftPane.tabs.map(\.currentURL) == [fallbackURL])
    }

    @Test func restoringActivePaneAndActiveTabsWorks() throws {
        let temporaryDirectory = try SessionTestTemporaryDirectory()
        let leftURL = try temporaryDirectory.createDirectory(named: "Left")
        let leftOtherURL = try temporaryDirectory.createDirectory(named: "Left Other")
        let rightURL = try temporaryDirectory.createDirectory(named: "Right")
        let leftActiveTabID = UUID()
        let rightActiveTabID = UUID()
        let state = SessionState(
            leftPane: SessionPaneState(
                tabs: [
                    SessionTabState(id: UUID(), currentURL: leftOtherURL),
                    SessionTabState(id: leftActiveTabID, currentURL: leftURL)
                ],
                activeTabID: leftActiveTabID,
                currentURL: leftURL,
                includeHiddenFiles: true,
                sortOption: .modifiedDate,
                sortDirection: .descending,
                directoriesFirst: false
            ),
            rightPane: SessionPaneState(
                tabs: [
                    SessionTabState(id: rightActiveTabID, currentURL: rightURL)
                ],
                activeTabID: rightActiveTabID,
                currentURL: rightURL,
                includeHiddenFiles: false,
                sortOption: .size,
                sortDirection: .ascending,
                directoriesFirst: true
            ),
            activePaneSide: .right,
            splitLeftPaneFraction: 0.42
        )

        let viewModel = DualPaneViewModel.restoring(state)

        #expect(viewModel.activePaneSide == .right)
        #expect(viewModel.leftPane.activeTabID == leftActiveTabID)
        #expect(viewModel.leftPane.currentURL == leftURL)
        #expect(viewModel.leftPane.includeHiddenFiles)
        #expect(viewModel.leftPane.sortOption == .modifiedDate)
        #expect(viewModel.leftPane.sortDirection == .descending)
        #expect(!viewModel.leftPane.directoriesFirst)
        #expect(viewModel.rightPane.activeTabID == rightActiveTabID)
        #expect(viewModel.rightPane.currentURL == rightURL)
        #expect(viewModel.splitLeftPaneFraction == 0.42)
    }

    @Test func corruptSavedDataFallsBackSafely() {
        let suiteName = "OpenPaneSessionTests-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let key = "Session"
        userDefaults.set(Data("not-json".utf8), forKey: key)
        let service = UserDefaultsSessionPersistenceService(userDefaults: userDefaults, key: key)

        #expect(service.loadSession() == nil)
    }

    @Test func debouncedSaveWritesLatestState() async throws {
        let service = MockSessionPersistenceService()
        let controller = SessionAutosaveController(
            service: service,
            debounceNanoseconds: 25_000_000
        )
        var firstState = sampleSessionState()
        var secondState = sampleSessionState()
        firstState.activePaneSide = .left
        secondState.activePaneSide = .right

        controller.scheduleSave(firstState)
        controller.scheduleSave(secondState)
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(service.savedStates == [secondState])
    }

    private func sampleSessionState() -> SessionState {
        let leftTabID = UUID()
        let rightTabID = UUID()
        return SessionState(
            leftPane: SessionPaneState(
                tabs: [SessionTabState(id: leftTabID, currentURL: URL(filePath: "/tmp", directoryHint: .isDirectory))],
                activeTabID: leftTabID,
                currentURL: URL(filePath: "/tmp", directoryHint: .isDirectory),
                includeHiddenFiles: true,
                sortOption: .name,
                sortDirection: .ascending,
                directoriesFirst: true
            ),
            rightPane: SessionPaneState(
                tabs: [SessionTabState(id: rightTabID, currentURL: URL(filePath: "/", directoryHint: .isDirectory))],
                activeTabID: rightTabID,
                currentURL: URL(filePath: "/", directoryHint: .isDirectory),
                includeHiddenFiles: false,
                sortOption: .kind,
                sortDirection: .descending,
                directoriesFirst: false
            ),
            activePaneSide: .left,
            splitLeftPaneFraction: 0.5
        )
    }
}

@MainActor
private final class MockSessionPersistenceService: SessionPersistenceServicing, @unchecked Sendable {
    private(set) var savedStates: [SessionState] = []
    var loadedState: SessionState?

    func loadSession() -> SessionState? {
        loadedState
    }

    func saveSession(_ state: SessionState) {
        savedStates.append(state)
    }
}

private struct SessionTestTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenPaneSessionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createDirectory(named name: String) throws -> URL {
        let directoryURL = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
