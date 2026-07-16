# Changelog

All notable changes to OpenPane will be documented in this file.

## Unreleased

### Added

- Explicit recursive Contents search for local UTF-8 files, with case-insensitive literal matching, first-line snippets, and skipped-file counts.
- Byte-level progress for copy, paste, duplicate, and cross-volume moves, backed by macOS `copyfile` metadata-preserving transfers.
- A resizable, persistent right-side preview panel with native Quick Look rendering, media controls, and an independently scrollable metadata inspector.
- Lightweight file details for dates, sizes, type identifiers, paths, ownership, permissions, tags, and matching image, PDF, media, and application formats.
- Safe Quick Edit for strict UTF-8 and UTF-16 text files up to 10 MiB, with encoding/BOM preservation, external-change detection, and metadata-preserving staged saves on local and mounted SMB volumes.
- Unsaved-edit guards for selection changes, panel hiding, window closing, and application termination.

### Changed

- Same-volume moves keep the fast rename path and item-level progress.
- Copy-style transfers stage destination output before atomic publication; cancelling removes only the incomplete staged item.
- Existing sessions decode with the preview visible at a 320-point default width; narrow windows collapse only clean preview panels.
- Movie files use a static cached Quick Look thumbnail in the embedded panel, fall back to a generic clapboard, and skip duration/resolution inspection above 256 MiB.
- Preview details now use a native recycling list that preserves scroll position during metadata enrichment and resets only when selection changes.

## v0.1.0

Initial MVP release.

### Added

- Native macOS SwiftUI dual-pane file browser.
- Persistent per-volume sidebar visibility with a volume management picker.
- Finder-style Network destination with best-effort Bonjour SMB discovery.
- macOS-managed SMB Connect to Server flow with saved server addresses.
- Generic Tailscale support through MagicDNS hostnames and Tailscale IP addresses.
- SMB authentication stays in macOS/Keychain; OpenPane does not persist credentials or passwords.
- Per-pane tabs with independent locations and selection state.
- Mouse marquee selection with multi-item drag-and-drop between panes.
- Local file browsing with file icons and persistent, reorderable favorites.
- Copy and move between panes.
- Conflict handling for copy and move: cancel, skip, replace, and keep both.
- Rename, batch rename, and new folder actions.
- Move to Trash.
- Filter and explicit recursive-subtree filename search with progress and result counts.
- Go to Folder with tilde expansion, recent paths, and clickable breadcrumbs.
- Linked-pane navigation with mirror and one-way modes.
- Quick Look preview.
- Reveal in Finder and Open with default app actions.
- Per-item operation progress with the current filename and cancellation.
- Unit tests for models, services, and view models.
