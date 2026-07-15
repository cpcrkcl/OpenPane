# OpenPane

OpenPane is a local-first, open-source native macOS dual-pane file manager with optional SMB network connections.

The MVP is focused on fast, practical local file browsing and basic file operations. It is inspired by classic dual-pane file managers, with Bonjour SMB discovery and macOS-managed mounting for network shares. It has no cloud storage, folder sync, or in-app remote filesystem protocol.

## Screenshots

Screenshots will be added for the initial GitHub release.

- Main dual-pane window
- Conflict handling dialog
- Batch rename dialog

## Current MVP Features

- Dual-pane browsing
- Per-pane tabs
- Local file browsing
- Keyboard-native file selection, range selection, and type-ahead navigation
- Copy and move between panes
- Clipboard copy/paste with `Command-C` and `Command-V`
- Mouse dragging between panes moves selected items; external and same-pane drops use the configured Copy, Ask, or Move action
- Configurable default drop action (`Copy`, `Ask`, or `Move`) in Settings
- Conflict handling: cancel, skip, replace, and keep both
- Rename and batch rename
- New folder
- Move to Trash
- Persistent, reorderable favorites sidebar
- Linked-pane navigation with mirror and one-way modes
- Persistent volume visibility selection
- Network page with nearby SMB discovery
- Connect to Server for SMB hosts, including Tailscale MagicDNS names and `100.x` addresses
- File icons
- Filter and recursive-subtree filename search with progress and result counts
- Go to Folder with `~` expansion, recent paths, and clickable path breadcrumbs
- Quick Look preview
- Reveal in Finder and Open with default app
- Per-item operation progress with current filename and cancellation

## Safety

OpenPane uses macOS Move to Trash for deletion-style actions. It does not permanently delete files.

## Development Permissions

The development app target is currently unsandboxed so OpenPane can work as a local file manager across user folders. macOS privacy protections still apply; for protected locations, users may need to grant OpenPane Full Disk Access in System Settings > Privacy & Security. Network discovery may require Local Network permission on macOS 15 and later.

## Requirements

- macOS 14+
- Xcode
- Swift
- SwiftUI
- XCTest / Swift Testing

## Install

OpenPane is not distributed as a signed release build yet.

For now, install it by building from source:

1. Clone the repository.
2. Open `OpenPane.xcodeproj` in Xcode.
3. Select the `OpenPane` scheme.
4. Build and run the app on macOS 14 or later.

When release artifacts are available, they will be attached to GitHub Releases.

## Build Instructions

Open the project in Xcode:

```sh
open OpenPane.xcodeproj
```

Then select the OpenPane scheme and use Xcode's Build or Run button.

You can also build from Terminal:

```sh
xcodebuild build -project OpenPane.xcodeproj -scheme OpenPane -destination 'platform=macOS'
```

Run tests from Terminal:

```sh
xcodebuild test -project OpenPane.xcodeproj -scheme OpenPane -destination 'platform=macOS'
```

## Known Limitations

- SMB connections are mounted by macOS and then appear as ordinary mounted volumes; OpenPane does not yet implement an independent remote filesystem client.
- Authentication is handled by macOS and its Keychain flow. OpenPane rejects credentials in entered SMB URLs and never stores passwords.
- Bonjour discovery only finds SMB services advertised on the reachable local network. It does not enumerate every computer or share.
- Tailscale devices are not automatically listed. Connect to them using a MagicDNS hostname or Tailscale IP, and ensure the SMB service, route, firewall, and Tailscale ACLs permit access.
- OpenPane does not use a Tailscale SDK, CLI, API token, or app integration; Tailscale supplies the route or DNS name while macOS handles SMB authentication.
- No SFTP or other remote file systems yet.
- No cloud storage integrations.
- No folder sync.
- No signed or notarized release package yet.
- Operation progress is per item; byte-level progress is not implemented yet.
- Conflict handling is intentionally simple and applies one selected strategy to the operation.
- Recursive search is filename-based, not content search.
- Tabs are basic and included in the saved session.

## Project Structure

- `OpenPane/Models`
- `OpenPane/Services`
- `OpenPane/ViewModels`
- `OpenPane/Views`
- `OpenPane/Utilities`

## Keyboard Shortcuts

- `Command-,`: Open Settings
- `Command-[`: Back in the active pane
- `Command-]`: Forward in the active pane
- `Command-R`: Refresh active pane
- `Command-Shift-R`: Refresh both panes
- `Command-Up`: Go up in the active pane
- `Command-Shift-.`: Toggle hidden files in the active pane
- `Command-Option-C`: Copy selection to the other pane
- `Command-Option-M`: Move selection to the other pane
- `Command-Shift-N`: New folder
- `Command-Shift-F`: Search the active pane's subtree
- `Command-Shift-G`: Go to Folder
- `Up` / `Down`: Move file-list focus and selection
- `Shift-Up` / `Shift-Down`: Extend the selection range
- `Command-A`: Select all visible items
- `Home` / `End` / `Page Up` / `Page Down`: Move through the focused file list
- Type a filename prefix: Jump to the next matching item
- `Return`: Open the focused item
- `Command-Return`: Rename selected item
- `Space`: Quick Look preview
- `Command-C`: Copy selected files to the clipboard
- `Command-V`: Paste files into the active pane
- `Command-D`: Duplicate selected files
- `Command-Option-N`: New file
- `Command-Delete`: Move selection to Trash

## Roadmap

- SFTP support later
- Signed release builds
- Byte-level operation progress
- More advanced conflict review
- File content search

## License

OpenPane is released under the MIT License. See [LICENSE](LICENSE).
