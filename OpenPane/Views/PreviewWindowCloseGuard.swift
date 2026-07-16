//
//  PreviewWindowCloseGuard.swift
//  OpenPane
//

import AppKit
import SwiftUI

/// Defers window closing while the preview editor has unsaved changes. The
/// proxy preserves SwiftUI/AppKit's existing window delegate behavior and is
/// retained by the representable coordinator for exactly the view lifetime.
struct PreviewWindowCloseGuard: NSViewRepresentable {
    @ObservedObject var sessionCoordinator: PreviewEditSessionCoordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionCoordinator: sessionCoordinator)
    }

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: AttachmentView, context: Context) {
        context.coordinator.sessionCoordinator = sessionCoordinator
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: AttachmentView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var sessionCoordinator: PreviewEditSessionCoordinator
        private var delegateProxy: WindowDelegateProxy?
        private weak var attachedWindow: NSWindow?

        init(sessionCoordinator: PreviewEditSessionCoordinator) {
            self.sessionCoordinator = sessionCoordinator
        }

        func attach(to window: NSWindow?) {
            guard attachedWindow !== window else { return }
            detach()
            guard let window else { return }

            let proxy = WindowDelegateProxy(
                originalDelegate: window.delegate,
                sessionCoordinator: sessionCoordinator
            )
            proxy.window = window
            attachedWindow = window
            delegateProxy = proxy
            window.delegate = proxy
            PreviewEditSessionRegistry.shared.register(
                window: window,
                sessionCoordinator: sessionCoordinator
            )
        }

        func detach() {
            guard let attachedWindow else { return }
            PreviewEditSessionRegistry.shared.unregister(window: attachedWindow)
            if attachedWindow.delegate === delegateProxy {
                attachedWindow.delegate = delegateProxy?.originalDelegate
            }
            self.attachedWindow = nil
            delegateProxy = nil
        }
    }
}

extension PreviewWindowCloseGuard {
    final class AttachmentView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    final class WindowDelegateProxy: NSObject, NSWindowDelegate {
        weak var originalDelegate: NSWindowDelegate?
        weak var window: NSWindow?
        var sessionCoordinator: PreviewEditSessionCoordinator
        private var bypassesNextClose = false

        init(
            originalDelegate: NSWindowDelegate?,
            sessionCoordinator: PreviewEditSessionCoordinator
        ) {
            self.originalDelegate = originalDelegate
            self.sessionCoordinator = sessionCoordinator
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if bypassesNextClose {
                bypassesNextClose = false
                return originalDelegate?.windowShouldClose?(sender) ?? true
            }

            guard sessionCoordinator.isDirty else {
                return originalDelegate?.windowShouldClose?(sender) ?? true
            }

            _ = sessionCoordinator.requestClose(
                onDeferredResolution: { [weak self, weak sender] in
                    guard let self, let sender else { return }
                    self.bypassesNextClose = true
                    sender.performClose(nil)
                }
            )
            return false
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if originalDelegate?.responds(to: selector) == true {
                return originalDelegate
            }
            return super.forwardingTarget(for: selector)
        }
    }
}

@MainActor
final class PreviewEditSessionRegistry {
    static let shared = PreviewEditSessionRegistry()

    private final class Entry {
        weak var window: NSWindow?
        weak var sessionCoordinator: PreviewEditSessionCoordinator?

        init(window: NSWindow, sessionCoordinator: PreviewEditSessionCoordinator) {
            self.window = window
            self.sessionCoordinator = sessionCoordinator
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var isResolvingTermination = false

    var hasDirtySessions: Bool {
        compactEntries().contains { $0.sessionCoordinator?.isDirty == true }
    }

    func register(window: NSWindow, sessionCoordinator: PreviewEditSessionCoordinator) {
        entries[ObjectIdentifier(window)] = Entry(
            window: window,
            sessionCoordinator: sessionCoordinator
        )
    }

    func unregister(window: NSWindow) {
        entries[ObjectIdentifier(window)] = nil
    }

    func resolveApplicationTermination(completion: @escaping (Bool) -> Void) {
        guard !isResolvingTermination else { return }
        isResolvingTermination = true
        let dirtyEntries = compactEntries().filter { $0.sessionCoordinator?.isDirty == true }

        func resolve(at index: Int) {
            guard index < dirtyEntries.count else {
                isResolvingTermination = false
                completion(true)
                return
            }

            let entry = dirtyEntries[index]
            guard let sessionCoordinator = entry.sessionCoordinator else {
                resolve(at: index + 1)
                return
            }
            entry.window?.makeKeyAndOrderFront(nil)
            if sessionCoordinator.requestClose(
                onDeferredResolution: {
                    resolve(at: index + 1)
                },
                onCancelled: {
                    self.isResolvingTermination = false
                    completion(false)
                }
            ) {
                resolve(at: index + 1)
            }
        }

        resolve(at: 0)
    }

    @discardableResult
    private func compactEntries() -> [Entry] {
        entries = entries.filter { _, entry in
            entry.window != nil && entry.sessionCoordinator != nil
        }
        return Array(entries.values)
    }
}
