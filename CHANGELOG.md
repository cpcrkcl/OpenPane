# Changelog

All notable changes to OpenPane will be documented in this file.

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
