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
        var state = sampleSessionState()
        state.isPreviewPanelVisible = false
        state.previewPanelWidth = 412
        let data = try JSONEncoder().encode(state)

        let decoded = try JSONDecoder().decode(SessionState.self, from: data)

        #expect(decoded == state)
    }

    @Test func legacySessionDefaultsToVisiblePreviewPanel() throws {
        let state = sampleSessionState()
        let encoded = try JSONEncoder().encode(state)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "isPreviewPanelVisible")
        object.removeValue(forKey: "previewPanelWidth")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SessionState.self, from: legacyData)

        #expect(decoded.isPreviewPanelVisible)
        #expect(decoded.previewPanelWidth == 320)
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
                sortDirection: .descending
            ),
            rightPane: SessionPaneState(
                tabs: [
                    SessionTabState(id: rightActiveTabID, currentURL: rightURL)
                ],
                activeTabID: rightActiveTabID,
                currentURL: rightURL,
                includeHiddenFiles: false,
                sortOption: .size,
                sortDirection: .ascending
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
        #expect(viewModel.rightPane.activeTabID == rightActiveTabID)
        #expect(viewModel.rightPane.currentURL == rightURL)
        #expect(viewModel.splitLeftPaneFraction == 0.42)
        #expect(viewModel.isPreviewPanelVisible)
        #expect(viewModel.previewPanelWidth == 320)
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
        let didSave = try await waitUntil {
            service.savedStates == [secondState]
        }

        #expect(didSave)
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
                sortDirection: .ascending
            ),
            rightPane: SessionPaneState(
                tabs: [SessionTabState(id: rightTabID, currentURL: URL(filePath: "/", directoryHint: .isDirectory))],
                activeTabID: rightTabID,
                currentURL: URL(filePath: "/", directoryHint: .isDirectory),
                includeHiddenFiles: false,
                sortOption: .kind,
                sortDirection: .descending
            ),
            activePaneSide: .left,
            splitLeftPaneFraction: 0.5
        )
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    intervalNanoseconds: UInt64 = 10_000_000,
    condition: () -> Bool
) async throws -> Bool {
    var remainingNanoseconds = timeoutNanoseconds

    while !condition() {
        guard remainingNanoseconds > 0 else {
            return false
        }

        let sleepNanoseconds = min(intervalNanoseconds, remainingNanoseconds)
        try await Task.sleep(nanoseconds: sleepNanoseconds)
        remainingNanoseconds -= sleepNanoseconds
    }

    return true
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
