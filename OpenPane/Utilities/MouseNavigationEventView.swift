//
//  MouseNavigationEventView.swift
//  OpenPane
//

import AppKit
import SwiftUI

enum MouseNavigationButton: Int {
    // macOS side-button numbering can vary by mouse and driver. Swap these raw
    // values if a device reports its Back and Forward buttons in reverse.
    case back = 3
    case forward = 4
}

struct MouseNavigationEventView: NSViewRepresentable {
    let onBack: () -> Void
    let onForward: () -> Void

    func makeNSView(context: Context) -> MouseNavigationMonitorView {
        MouseNavigationMonitorView(onBack: onBack, onForward: onForward)
    }

    func updateNSView(_ nsView: MouseNavigationMonitorView, context: Context) {
        nsView.onBack = onBack
        nsView.onForward = onForward
    }

    static func dismantleNSView(_ nsView: MouseNavigationMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

final class MouseNavigationMonitorView: NSView {
    var onBack: () -> Void
    var onForward: () -> Void

    private var eventMonitor: Any?

    init(onBack: @escaping () -> Void, onForward: @escaping () -> Void) {
        self.onBack = onBack
        self.onForward = onForward
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopMonitoring()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    func stopMonitoring() {
        guard let eventMonitor else {
            return
        }

        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func startMonitoring() {
        guard eventMonitor == nil else {
            return
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self,
                  NSApp.isActive,
                  let window = self.window,
                  window.isKeyWindow,
                  event.window === window,
                  let navigationButton = MouseNavigationButton(rawValue: event.buttonNumber) else {
                return event
            }

            switch navigationButton {
            case .back:
                self.onBack()
            case .forward:
                self.onForward()
            }

            return nil
        }
    }
}
