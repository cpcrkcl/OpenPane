//
//  LightweightPreviewDetailsView.swift
//  OpenPane
//

import AppKit
import SwiftUI

nonisolated struct PreviewDetailRow: Hashable, Sendable {
    let title: String
    let value: String
    let isSelectable: Bool
    let allowsWrapping: Bool
}

nonisolated struct PreviewDetailSection: Hashable, Sendable {
    let title: String
    let rows: [PreviewDetailRow]
}

/// A native, recycling details list. The previous nested SwiftUI scroll view
/// repeatedly laid out every selectable field while scrolling; NSTableView
/// keeps only the visible rows active and reloads only when metadata changes.
struct LightweightPreviewDetailsView: NSViewRepresentable {
    let targetID: URL
    let sections: [PreviewDetailSection]
    let isLoading: Bool

    func makeNSView(context: Context) -> LightweightPreviewDetailsContainerView {
        LightweightPreviewDetailsContainerView()
    }

    func updateNSView(_ view: LightweightPreviewDetailsContainerView, context: Context) {
        view.update(targetID: targetID, sections: sections, isLoading: isLoading)
    }
}

@MainActor
final class LightweightPreviewDetailsContainerView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private enum Item: Hashable {
        case loading
        case header(String)
        case detail(PreviewDetailRow)
    }

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var items: [Item] = []
    private var renderedTargetID: URL?
    private var renderedSections: [PreviewDetailSection] = []
    private var renderedIsLoading = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("details"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = NSColor(CatppuccinMochaTheme.paneBackground)
        tableView.gridStyleMask = []
        tableView.intercellSpacing = .zero
        tableView.rowHeight = 24
        tableView.usesAutomaticRowHeights = true
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(CatppuccinMochaTheme.paneBackground)
        scrollView.borderType = .noBorder
        scrollView.setAccessibilityLabel("File Details")

        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }

    func update(targetID: URL, sections: [PreviewDetailSection], isLoading: Bool) {
        let targetChanged = renderedTargetID != targetID
        let contentChanged = renderedSections != sections || renderedIsLoading != isLoading
        guard targetChanged || contentChanged else { return }

        let previousOrigin = scrollView.contentView.bounds.origin
        renderedTargetID = targetID
        renderedSections = sections
        renderedIsLoading = isLoading
        items = isLoading
            ? [.loading]
            : sections.flatMap { section in
                [.header(section.title)] + section.rows.map(Item.detail)
            }
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()

        let newOrigin = targetChanged ? NSPoint.zero : previousOrigin
        scrollView.contentView.scroll(to: newOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard items.indices.contains(row) else { return nil }

        switch items[row] {
        case .loading:
            let identifier = NSUserInterfaceItemIdentifier("loading")
            let view = tableView.makeView(withIdentifier: identifier, owner: self) as? PreviewLoadingCell
                ?? PreviewLoadingCell()
            view.identifier = identifier
            return view

        case .header(let title):
            let identifier = NSUserInterfaceItemIdentifier("header")
            let view = tableView.makeView(withIdentifier: identifier, owner: self) as? PreviewSectionHeaderCell
                ?? PreviewSectionHeaderCell()
            view.identifier = identifier
            view.configure(title: title)
            return view

        case .detail(let detail):
            let identifier = NSUserInterfaceItemIdentifier("detail")
            let view = tableView.makeView(withIdentifier: identifier, owner: self) as? PreviewDetailCell
                ?? PreviewDetailCell()
            view.identifier = identifier
            view.configure(detail)
            return view
        }
    }
}

@MainActor
private final class PreviewLoadingCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "Loading details…")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 12)
        label.textColor = NSColor(CatppuccinMochaTheme.mutedText)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class PreviewSectionHeaderCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = NSColor(CatppuccinMochaTheme.mutedText)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        label.attributedStringValue = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor(CatppuccinMochaTheme.mutedText),
                .kern: 0.55
            ]
        )
    }
}

@MainActor
private final class PreviewDetailCell: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleField.font = .systemFont(ofSize: 11, weight: .medium)
        titleField.textColor = NSColor(CatppuccinMochaTheme.mutedText)
        titleField.alignment = .right
        titleField.setContentHuggingPriority(.required, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.required, for: .horizontal)

        valueField.font = .systemFont(ofSize: 11)
        valueField.textColor = NSColor(CatppuccinMochaTheme.primaryText)
        valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        valueField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)
        addSubview(valueField)

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            titleField.widthAnchor.constraint(equalToConstant: 82),

            valueField.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 8),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            valueField.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            valueField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            titleField.firstBaselineAnchor.constraint(equalTo: valueField.firstBaselineAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ detail: PreviewDetailRow) {
        titleField.stringValue = detail.title
        valueField.stringValue = detail.value
        valueField.isSelectable = detail.isSelectable
        valueField.maximumNumberOfLines = detail.allowsWrapping ? 0 : 2
        valueField.lineBreakMode = detail.allowsWrapping ? .byCharWrapping : .byTruncatingTail
        valueField.cell?.wraps = detail.allowsWrapping
        valueField.toolTip = detail.allowsWrapping ? nil : detail.value
    }
}
