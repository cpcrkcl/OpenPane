//
//  PlainTextEditorView.swift
//  OpenPane
//

import AppKit
import Combine
import SwiftUI

/// Owns the editor's mutable text storage. Keeping the live draft here avoids
/// copying a potentially multi-megabyte String through a SwiftUI Binding on
/// every keystroke; the complete value is read only when Save is requested.
@MainActor
final class PlainTextEditorBuffer: NSObject, ObservableObject, NSTextStorageDelegate {
    let textStorage: NSTextStorage

    @Published private(set) var isDirty = false

    init(text: String) {
        textStorage = NSTextStorage(string: text)
        super.init()
        textStorage.delegate = self
    }

    var stringForSaving: String {
        textStorage.string
    }

    func replace(with text: String, markClean: Bool = true) {
        textStorage.delegate = nil
        textStorage.replaceCharacters(
            in: NSRange(location: 0, length: textStorage.length),
            with: text
        )
        textStorage.delegate = self
        if markClean {
            isDirty = false
        }
    }

    func markSaved() {
        isDirty = false
    }

    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(NSTextStorageEditActions.editedCharacters) else {
            return
        }

        Task { @MainActor [weak self] in
            self?.isDirty = true
        }
    }
}

/// A native plain-text editor with AppKit undo, find, selection, clipboard,
/// accessibility, and line-wrapping behavior.
struct PlainTextEditorView: NSViewRepresentable {
    let buffer: PlainTextEditorBuffer
    var isEditable = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(CatppuccinMochaTheme.base)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        buffer.textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: NSFont.Weight.regular)
        textView.textColor = NSColor(CatppuccinMochaTheme.primaryText)
        textView.backgroundColor = NSColor(CatppuccinMochaTheme.base)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize.zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isEditable = isEditable
        textView.isSelectable = true

        scrollView.documentView = textView
        context.coordinator.layoutManager = layoutManager
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.textView?.isEditable = isEditable
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let layoutManager = coordinator.layoutManager {
            layoutManager.textStorage?.removeLayoutManager(layoutManager)
        }
        coordinator.textView = nil
        coordinator.layoutManager = nil
        scrollView.documentView = nil
    }

    final class Coordinator {
        fileprivate weak var textView: NSTextView?
        fileprivate var layoutManager: NSLayoutManager?
    }
}
