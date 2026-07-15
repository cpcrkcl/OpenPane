//
//  FileListSelectionControllerTests.swift
//  OpenPaneTests
//

import Foundation
import Testing
@testable import OpenPane

struct FileListSelectionControllerTests {
    private let entries = [
        FileListSelectionEntry(id: URL(filePath: "/Alpha"), name: "Alpha"),
        FileListSelectionEntry(id: URL(filePath: "/Bravo"), name: "Bravo"),
        FileListSelectionEntry(id: URL(filePath: "/Charlie"), name: "Charlie"),
        FileListSelectionEntry(id: URL(filePath: "/Delta"), name: "Delta")
    ]

    @Test func singleSelectionSetsFocusAnchorAndOrderedSelection() {
        var controller = FileListSelectionController()

        controller.selectOnly(entries[1].id, in: entries)

        #expect(controller.focusedID == entries[1].id)
        #expect(controller.selectionAnchorID == entries[1].id)
        #expect(controller.orderedSelectionIDs == [entries[1].id])
    }

    @Test func commandTogglePreservesVisibleOrder() {
        var controller = FileListSelectionController()

        controller.toggle(entries[2].id, in: entries)
        controller.toggle(entries[0].id, in: entries)
        #expect(controller.orderedSelectionIDs == [entries[0].id, entries[2].id])

        controller.toggle(entries[2].id, in: entries)
        #expect(controller.orderedSelectionIDs == [entries[0].id])
        #expect(controller.focusedID == entries[2].id)
    }

    @Test func shiftSelectionUsesAnchorAndVisibleOrder() {
        var controller = FileListSelectionController()
        controller.selectOnly(entries[1].id, in: entries)

        controller.selectRange(to: entries[3].id, in: entries)

        #expect(controller.selectionAnchorID == entries[1].id)
        #expect(controller.focusedID == entries[3].id)
        #expect(controller.orderedSelectionIDs == entries[1...3].map(\.id))
    }

    @Test func selectAllSelectsEveryVisibleEntry() {
        var controller = FileListSelectionController()

        controller.selectAll(in: entries)

        #expect(controller.orderedSelectionIDs == entries.map(\.id))
        #expect(controller.focusedID == entries[0].id)
    }

    @Test func marqueeSelectionPreservesVisibleOrderAndSupportsAdding() {
        var controller = FileListSelectionController()

        controller.select(
            Set([entries[1].id, entries[3].id]),
            addingToSelection: false,
            in: entries
        )

        #expect(controller.orderedSelectionIDs == [entries[1].id, entries[3].id])
        #expect(controller.focusedID == entries[3].id)

        controller.select(
            Set([entries[0].id]),
            addingToSelection: true,
            in: entries
        )

        #expect(controller.orderedSelectionIDs == [entries[0].id, entries[1].id, entries[3].id])
        #expect(controller.selectionAnchorID == entries[0].id)
    }

    @Test func arrowMovementReplacesOrExtendsSelection() {
        var controller = FileListSelectionController()

        let initialFocus = controller.moveFocus(by: 1, extendingSelection: false, in: entries)
        #expect(initialFocus == entries[0].id)
        #expect(controller.orderedSelectionIDs == [entries[0].id])

        let extendedFocus = controller.moveFocus(by: 2, extendingSelection: true, in: entries)
        #expect(extendedFocus == entries[2].id)
        #expect(controller.orderedSelectionIDs == entries[0...2].map(\.id))

        _ = controller.moveFocus(by: -1, extendingSelection: false, in: entries)
        #expect(controller.orderedSelectionIDs == [entries[1].id])
    }

    @Test func typeAheadAccumulatesThenResetsAfterTimeout() {
        let typeAheadEntries = [
            FileListSelectionEntry(id: URL(filePath: "/Alpine"), name: "Alpine"),
            FileListSelectionEntry(id: URL(filePath: "/Bravo"), name: "Bravo"),
            FileListSelectionEntry(id: URL(filePath: "/Blue"), name: "Blue")
        ]
        let start = Date(timeIntervalSince1970: 10)
        var controller = FileListSelectionController()

        #expect(controller.typeAhead("b", in: typeAheadEntries, now: start) == typeAheadEntries[1].id)
        #expect(controller.typeAhead("l", in: typeAheadEntries, now: start.addingTimeInterval(0.2)) == typeAheadEntries[2].id)
        #expect(controller.typeAhead("a", in: typeAheadEntries, now: start.addingTimeInterval(1.2)) == typeAheadEntries[0].id)
    }

    @Test func reconciliationClampsFocusAndSelectionWhenListShrinks() {
        var controller = FileListSelectionController()
        controller.selectOnly(entries[3].id, in: entries)

        let shortenedEntries = Array(entries.prefix(2))
        controller.reconcile(
            entries: shortenedEntries,
            selectedIDs: Set(controller.orderedSelectionIDs)
        )

        #expect(controller.focusedID == shortenedEntries[1].id)
        #expect(controller.orderedSelectionIDs == [shortenedEntries[1].id])
        #expect(controller.selectionAnchorID == shortenedEntries[1].id)
    }
}
