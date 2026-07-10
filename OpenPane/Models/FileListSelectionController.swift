//
//  FileListSelectionController.swift
//  OpenPane
//

import Foundation

nonisolated struct FileListSelectionEntry: Equatable, Sendable {
    let id: URL
    let name: String
}

nonisolated struct FileListSelectionController: Equatable, Sendable {
    private(set) var focusedID: URL?
    private(set) var selectionAnchorID: URL?
    private(set) var orderedSelectionIDs: [URL] = []

    private var focusedIndexHint = 0
    private var typeAheadQuery = ""
    private var lastTypeAheadInputDate: Date?

    mutating func selectOnly(_ id: URL, in entries: [FileListSelectionEntry]) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            reconcile(entries: entries, selectedIDs: Set(orderedSelectionIDs))
            return
        }

        focusedID = id
        selectionAnchorID = id
        focusedIndexHint = index
        orderedSelectionIDs = [id]
        resetTypeAhead()
    }

    mutating func toggle(_ id: URL, in entries: [FileListSelectionEntry]) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            reconcile(entries: entries, selectedIDs: Set(orderedSelectionIDs))
            return
        }

        var selectedIDs = Set(orderedSelectionIDs)
        if !selectedIDs.insert(id).inserted {
            selectedIDs.remove(id)
        }

        focusedID = id
        selectionAnchorID = id
        focusedIndexHint = index
        orderedSelectionIDs = entries.map(\.id).filter(selectedIDs.contains)
        resetTypeAhead()
    }

    mutating func focus(_ id: URL, in entries: [FileListSelectionEntry]) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }

        focusedID = id
        selectionAnchorID = id
        focusedIndexHint = index
        resetTypeAhead()
    }

    mutating func selectRange(to id: URL, in entries: [FileListSelectionEntry]) {
        guard let targetIndex = entries.firstIndex(where: { $0.id == id }) else {
            reconcile(entries: entries, selectedIDs: Set(orderedSelectionIDs))
            return
        }

        let anchorIndex = selectionAnchorID
            .flatMap { anchorID in entries.firstIndex(where: { $0.id == anchorID }) }
            ?? focusedID.flatMap { focusedID in entries.firstIndex(where: { $0.id == focusedID }) }
            ?? targetIndex
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)

        selectionAnchorID = entries[anchorIndex].id
        focusedID = id
        focusedIndexHint = targetIndex
        orderedSelectionIDs = bounds.map { entries[$0].id }
        resetTypeAhead()
    }

    @discardableResult
    mutating func moveFocus(
        by offset: Int,
        extendingSelection: Bool,
        in entries: [FileListSelectionEntry]
    ) -> URL? {
        guard !entries.isEmpty else {
            clear()
            return nil
        }

        let currentIndex = focusedID
            .flatMap { focusedID in entries.firstIndex(where: { $0.id == focusedID }) }
        let targetIndex: Int
        if let currentIndex {
            targetIndex = min(max(currentIndex + offset, 0), entries.count - 1)
        } else {
            targetIndex = offset < 0 ? entries.count - 1 : 0
        }
        return moveFocus(toIndex: targetIndex, extendingSelection: extendingSelection, in: entries)
    }

    @discardableResult
    mutating func moveFocus(
        toIndex index: Int,
        extendingSelection: Bool,
        in entries: [FileListSelectionEntry]
    ) -> URL? {
        guard !entries.isEmpty else {
            clear()
            return nil
        }

        let targetIndex = min(max(index, 0), entries.count - 1)
        let targetID = entries[targetIndex].id

        if extendingSelection {
            if selectionAnchorID == nil {
                selectionAnchorID = focusedID ?? targetID
            }
            selectRange(to: targetID, in: entries)
        } else {
            selectOnly(targetID, in: entries)
        }

        return targetID
    }

    mutating func selectAll(in entries: [FileListSelectionEntry]) {
        guard !entries.isEmpty else {
            clear()
            return
        }

        if focusedID == nil || !entries.contains(where: { $0.id == focusedID }) {
            focusedID = entries[0].id
            focusedIndexHint = 0
        }
        selectionAnchorID = focusedID
        orderedSelectionIDs = entries.map(\.id)
        resetTypeAhead()
    }

    @discardableResult
    mutating func typeAhead(
        _ characters: String,
        in entries: [FileListSelectionEntry],
        now: Date = Date(),
        resetInterval: TimeInterval = 0.9
    ) -> URL? {
        let normalizedCharacters = characters.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        guard !normalizedCharacters.isEmpty, !entries.isEmpty else {
            return nil
        }

        if let lastTypeAheadInputDate,
           now.timeIntervalSince(lastTypeAheadInputDate) <= resetInterval {
            typeAheadQuery += normalizedCharacters
        } else {
            typeAheadQuery = normalizedCharacters
        }
        lastTypeAheadInputDate = now

        let currentIndex = focusedID
            .flatMap { focusedID in entries.firstIndex(where: { $0.id == focusedID }) }
        let startIndex = currentIndex.map { ($0 + 1) % entries.count } ?? 0

        if let match = matchingEntry(
            query: typeAheadQuery,
            startIndex: startIndex,
            entries: entries
        ) {
            let matchedQuery = typeAheadQuery
            selectOnly(match.id, in: entries)
            typeAheadQuery = matchedQuery
            lastTypeAheadInputDate = now
            return match.id
        }

        guard typeAheadQuery != normalizedCharacters,
              let fallbackMatch = matchingEntry(
                query: normalizedCharacters,
                startIndex: startIndex,
                entries: entries
              ) else {
            return nil
        }

        typeAheadQuery = normalizedCharacters
        selectOnly(fallbackMatch.id, in: entries)
        typeAheadQuery = normalizedCharacters
        lastTypeAheadInputDate = now
        return fallbackMatch.id
    }

    mutating func synchronize(
        selectedIDs: Set<URL>,
        entries: [FileListSelectionEntry]
    ) {
        orderedSelectionIDs = entries.map(\.id).filter(selectedIDs.contains)

        if let focusedID,
           entries.contains(where: { $0.id == focusedID }) {
            focusedIndexHint = entries.firstIndex(where: { $0.id == focusedID }) ?? focusedIndexHint
        } else if let lastSelectedID = orderedSelectionIDs.last,
                  let index = entries.firstIndex(where: { $0.id == lastSelectedID }) {
            focusedID = lastSelectedID
            focusedIndexHint = index
        } else {
            focusedID = nil
        }

        if let selectionAnchorID,
           !entries.contains(where: { $0.id == selectionAnchorID }) {
            self.selectionAnchorID = focusedID
        } else if selectionAnchorID == nil {
            selectionAnchorID = focusedID
        }
    }

    mutating func reconcile(
        entries: [FileListSelectionEntry],
        selectedIDs: Set<URL>
    ) {
        guard !entries.isEmpty else {
            clear()
            return
        }

        let hadFocus = focusedID != nil
        orderedSelectionIDs = entries.map(\.id).filter(selectedIDs.contains)

        if let focusedID,
           let focusedIndex = entries.firstIndex(where: { $0.id == focusedID }) {
            focusedIndexHint = focusedIndex
        } else if hadFocus {
            focusedIndexHint = min(max(focusedIndexHint, 0), entries.count - 1)
            focusedID = entries[focusedIndexHint].id
        } else {
            focusedID = nil
        }

        if let selectionAnchorID,
           !entries.contains(where: { $0.id == selectionAnchorID }) {
            self.selectionAnchorID = focusedID
        } else if selectionAnchorID == nil, focusedID != nil {
            selectionAnchorID = focusedID
        }

        if hadFocus, orderedSelectionIDs.isEmpty, let focusedID {
            orderedSelectionIDs = [focusedID]
        }
    }

    mutating func clear() {
        focusedID = nil
        selectionAnchorID = nil
        orderedSelectionIDs = []
        focusedIndexHint = 0
        resetTypeAhead()
    }

    private func matchingEntry(
        query: String,
        startIndex: Int,
        entries: [FileListSelectionEntry]
    ) -> FileListSelectionEntry? {
        for offset in 0..<entries.count {
            let entry = entries[(startIndex + offset) % entries.count]
            let normalizedName = entry.name.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            if normalizedName.hasPrefix(query) {
                return entry
            }
        }

        return nil
    }

    private mutating func resetTypeAhead() {
        typeAheadQuery = ""
        lastTypeAheadInputDate = nil
    }
}
