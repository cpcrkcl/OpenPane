//
//  TrailingPaneSplitView.swift
//  OpenPane
//

import AppKit
import SwiftUI

struct TrailingPaneSplitView<Browser: View, Trailing: View>: NSViewRepresentable {
    let totalWidth: CGFloat
    let desiredTrailingWidth: CGFloat
    let dividerWidth: CGFloat
    let minimumBrowserWidth: CGFloat
    let minimumTrailingWidth: CGFloat
    let maximumTrailingWidth: CGFloat
    let browser: Browser
    let trailing: Trailing
    let onCommit: (CGFloat) -> Void

    init(
        totalWidth: CGFloat,
        desiredTrailingWidth: CGFloat,
        dividerWidth: CGFloat,
        minimumBrowserWidth: CGFloat,
        minimumTrailingWidth: CGFloat,
        maximumTrailingWidth: CGFloat,
        @ViewBuilder browser: () -> Browser,
        @ViewBuilder trailing: () -> Trailing,
        onCommit: @escaping (CGFloat) -> Void
    ) {
        self.totalWidth = totalWidth
        self.desiredTrailingWidth = desiredTrailingWidth
        self.dividerWidth = dividerWidth
        self.minimumBrowserWidth = minimumBrowserWidth
        self.minimumTrailingWidth = minimumTrailingWidth
        self.maximumTrailingWidth = maximumTrailingWidth
        self.browser = browser()
        self.trailing = trailing()
        self.onCommit = onCommit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommit: onCommit)
    }

    func makeNSView(context: Context) -> TrailingPaneSplitContainerView {
        let view = TrailingPaneSplitContainerView(
            browser: AnyView(browser),
            trailing: AnyView(trailing)
        )
        view.commitHandler = context.coordinator.commit
        return view
    }

    func updateNSView(_ nsView: TrailingPaneSplitContainerView, context: Context) {
        context.coordinator.onCommit = onCommit
        nsView.commitHandler = context.coordinator.commit
        nsView.update(
            browser: AnyView(browser),
            trailing: AnyView(trailing),
            totalWidth: totalWidth,
            desiredTrailingWidth: desiredTrailingWidth,
            dividerWidth: dividerWidth,
            minimumBrowserWidth: minimumBrowserWidth,
            minimumTrailingWidth: minimumTrailingWidth,
            maximumTrailingWidth: maximumTrailingWidth
        )
    }

    final class Coordinator {
        var onCommit: (CGFloat) -> Void

        init(onCommit: @escaping (CGFloat) -> Void) {
            self.onCommit = onCommit
        }

        func commit(_ width: CGFloat) {
            onCommit(width)
        }
    }
}

final class TrailingPaneSplitContainerView: NSView {
    var commitHandler: ((CGFloat) -> Void)?

    private let browserHostingView: NSHostingView<AnyView>
    private let trailingHostingView: NSHostingView<AnyView>
    private let divider = TrailingPaneDividerView()
    private let dragPreview = TrailingPaneDragPreviewView()
    private var configuredTotalWidth: CGFloat = 0
    private var dividerWidth: CGFloat = 10
    private var minimumBrowserWidth: CGFloat = 0
    private var minimumTrailingWidth: CGFloat = 0
    private var maximumTrailingWidth: CGFloat = .greatestFiniteMagnitude
    private var committedTrailingWidth: CGFloat = 0
    private var dragStartTrailingWidth: CGFloat?
    private var previewTrailingWidth: CGFloat?

    init(browser: AnyView, trailing: AnyView) {
        browserHostingView = NSHostingView(rootView: browser)
        trailingHostingView = NSHostingView(rootView: trailing)
        super.init(frame: .zero)
        wantsLayer = true
        divider.onBegin = { [weak self] in self?.beginDragging() }
        divider.onDrag = { [weak self] delta in self?.drag(by: delta) }
        divider.onEnd = { [weak self] in self?.endDragging() }
        dragPreview.isHidden = true
        addSubview(browserHostingView)
        addSubview(trailingHostingView)
        addSubview(divider)
        addSubview(dragPreview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func update(
        browser: AnyView,
        trailing: AnyView,
        totalWidth: CGFloat,
        desiredTrailingWidth: CGFloat,
        dividerWidth: CGFloat,
        minimumBrowserWidth: CGFloat,
        minimumTrailingWidth: CGFloat,
        maximumTrailingWidth: CGFloat
    ) {
        browserHostingView.rootView = browser
        trailingHostingView.rootView = trailing
        configuredTotalWidth = totalWidth
        self.dividerWidth = dividerWidth
        self.minimumBrowserWidth = minimumBrowserWidth
        self.minimumTrailingWidth = minimumTrailingWidth
        self.maximumTrailingWidth = maximumTrailingWidth
        guard dragStartTrailingWidth == nil else { return }
        committedTrailingWidth = clamped(desiredTrailingWidth)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let totalWidth = resolvedTotalWidth
        let trailingWidth = clamped(committedTrailingWidth)
        committedTrailingWidth = trailingWidth
        let safeDividerWidth = min(max(0, dividerWidth), totalWidth)
        let browserWidth = max(0, totalWidth - safeDividerWidth - trailingWidth)
        browserHostingView.frame = NSRect(x: 0, y: 0, width: browserWidth, height: bounds.height)
        divider.frame = NSRect(x: browserWidth, y: 0, width: safeDividerWidth, height: bounds.height)
        trailingHostingView.frame = NSRect(
            x: browserWidth + safeDividerWidth,
            y: 0,
            width: trailingWidth,
            height: bounds.height
        )

        if let previewTrailingWidth {
            let previewX = totalWidth - safeDividerWidth - clamped(previewTrailingWidth)
            dragPreview.frame = NSRect(x: previewX, y: 0, width: safeDividerWidth, height: bounds.height)
        }
    }

    private func beginDragging() {
        dragStartTrailingWidth = committedTrailingWidth
        previewTrailingWidth = committedTrailingWidth
        dragPreview.isHidden = false
        needsLayout = true
    }

    private func drag(by deltaX: CGFloat) {
        let startingWidth = dragStartTrailingWidth ?? committedTrailingWidth
        previewTrailingWidth = clamped(startingWidth - deltaX)
        needsLayout = true
    }

    private func endDragging() {
        committedTrailingWidth = previewTrailingWidth ?? committedTrailingWidth
        dragStartTrailingWidth = nil
        previewTrailingWidth = nil
        dragPreview.isHidden = true
        needsLayout = true
        commitHandler?(committedTrailingWidth)
    }

    private func clamped(_ proposedWidth: CGFloat) -> CGFloat {
        let available = max(0, resolvedTotalWidth - min(max(0, dividerWidth), resolvedTotalWidth))
        let maximumLeavingBrowser = max(0, available - max(0, minimumBrowserWidth))
        let upperBound = min(maximumTrailingWidth, max(minimumTrailingWidth, maximumLeavingBrowser))
        return min(max(proposedWidth, min(minimumTrailingWidth, available)), min(upperBound, available))
    }

    private var resolvedTotalWidth: CGFloat {
        bounds.width > 0 ? bounds.width : max(0, configuredTotalWidth)
    }
}

private final class TrailingPaneDividerView: NSView {
    var onBegin: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var dragStartLocation: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag to resize preview"
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityIdentifier("preview-split-divider")
        setAccessibilityLabel("Preview split divider")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds.insetBy(dx: -4, dy: 0), cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
        onBegin?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartLocation else { return }
        onDrag?(event.locationInWindow.x - dragStartLocation.x)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        onEnd?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(CatppuccinMochaTheme.surface0).setFill()
        bounds.fill()
        NSColor(CatppuccinMochaTheme.accent).withAlphaComponent(0.8).setFill()
        NSRect(x: bounds.midX - 0.5, y: 12, width: 1, height: max(0, bounds.height - 24)).fill()
    }
}

private final class TrailingPaneDragPreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(CatppuccinMochaTheme.accent).withAlphaComponent(0.9).setFill()
        bounds.fill()
    }
}
