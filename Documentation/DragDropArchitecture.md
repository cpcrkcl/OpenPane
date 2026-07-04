# OpenPane Drag and Drop Architecture Audit

This note captures the current pane, tab, and file-list structure before adding broader drag and drop behavior.

## Current Pane Ownership

`DualPaneViewModel` owns the left and right `FilePaneViewModel` instances, tracks the active pane, and coordinates operations that involve both panes. Copy, move, trash, duplicate, compress, paste, rename, folder creation, and file creation all flow through this layer and then use `FileOperationService`.

`FilePaneViewModel` owns the state for one pane. It tracks the current directory, loaded items, selection, loading/error state, sorting, search, recursive search, and tabs. It also contains helper behavior for context-menu target selection, opening, revealing, Quick Look, and clipboard path actions.

`FileOperationService` is the correct place for filesystem mutations. Views should continue to route operation requests through view models instead of calling `FileManager` directly.

## Tab Drag and Drop

Basic tab support already exists.

`FilePaneTab` stores a tab's `currentURL`, `items`, and `selectedItems`. Search, sorting, and hidden-file visibility are currently pane-level settings, not tab-level settings.

`FilePaneTabDragItem` is already defined as a Codable drag payload with a custom UTType: `cpcr.kcl.OpenPane.tab`.

`FilePaneView` starts tab drags from tab headers and accepts tab drops on tab headers or empty tab bar space. `DualPaneView` passes the drop request to `DualPaneViewModel.moveTab(tabID:from:to:at:)`, which reorders tabs within a pane or detaches the tab from the source pane and receives it in the destination pane.

The safest place to refine tab drag and drop is:

- Drag source and visual drop target: `FilePaneView` tab bar/tab header code.
- Cross-pane state mutation: `DualPaneViewModel.moveTab(tabID:from:to:at:)`.
- Per-pane tab state mutation: `FilePaneViewModel.detachTab(_:)` and `FilePaneViewModel.receiveTab(_:)`.

Current limitations to keep separate from file drag/drop:

- Same-pane tab reordering is exposed through tab-header and tab-bar drop targets.
- Cross-pane tab drops are intended for the other pane's tab bar, not arbitrary pane content.
- The tab payload carries tab identity, source pane side, and current URL, not a full serialized tab snapshot.

## File Drag and Drop

File row drag/drop is implemented.

`FilePaneRowView` starts file drags from rows. Drag selection mirrors context-menu behavior: if the dragged item is already selected, the drag operates on the full selected set; otherwise it operates on the dragged item only.

The pane's file-list/background container accepts file drops with the destination set to that pane's `currentURL`. Folder rows are also drop targets for directory items; regular file rows reject drops so a drag never looks like it might overwrite that file.

Recommended file drag payloads:

- Standard file URL representations for Finder interoperability.
- A small OpenPane internal payload, if needed, containing source pane side plus file URLs.

The safest place to orchestrate dropped file operations is `DualPaneViewModel`, using a new method such as `copyDroppedItems(_:toPane:)` or `moveDroppedItems(_:fromPane:toPane:)`. That method should reuse `FileOperationService`, refresh the destination pane, and refresh the source pane for moves.

## Recommended Implementation Order

1. Keep the existing tab drag/drop state path and improve only the drop affordance if needed.
2. Keep file row drag sources aligned with the same target-selection rules used by context menus.
3. Keep pane/background and folder-row drop targets routed through `DualPaneViewModel`.
4. Route all filesystem work through `DualPaneViewModel` and `FileOperationService`.
5. Add move-with-modifier refinements as follow-up work.

## Risks to Watch

- Recursive search results may come from directories outside the pane's current directory.
- Dragging into the same directory should avoid accidental collisions or no-op confusion.
- Conflict handling should stay centralized in `FileOperationService`.
- External file drops may still require macOS privacy permissions for protected folders.
- Views should not grow new filesystem business logic while adding drag/drop UI.
