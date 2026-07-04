//
//  SessionPersistenceService.swift
//  OpenPane
//
//  Created by Codex on 7/3/26.
//

import Combine
import Foundation

@MainActor
protocol SessionPersistenceServicing: Sendable {
    func loadSession() -> SessionState?
    func saveSession(_ state: SessionState)
}

@MainActor
final class UserDefaultsSessionPersistenceService: SessionPersistenceServicing {
    private let userDefaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "OpenPaneSessionState"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadSession() -> SessionState? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? decoder.decode(SessionState.self, from: data)
    }

    func saveSession(_ state: SessionState) {
        guard let data = try? encoder.encode(state) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }
}

@MainActor
final class SessionAutosaveController: ObservableObject {
    private let service: any SessionPersistenceServicing
    private let debounceNanoseconds: UInt64
    private var saveTask: Task<Void, Never>?

    init(
        service: any SessionPersistenceServicing,
        debounceNanoseconds: UInt64 = 500_000_000
    ) {
        self.service = service
        self.debounceNanoseconds = debounceNanoseconds
    }

    deinit {
        saveTask?.cancel()
    }

    func scheduleSave(_ state: SessionState) {
        saveTask?.cancel()
        saveTask = Task { @MainActor [service, debounceNanoseconds] in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                service.saveSession(state)
            } catch {
                return
            }
        }
    }

    func saveImmediately(_ state: SessionState) {
        saveTask?.cancel()
        service.saveSession(state)
    }
}
