# OpenPane

OpenPane is a local-first, open-source native macOS dual-pane file manager.

The MVP is focused on fast, practical local file browsing and basic file operations. It is inspired by classic dual-pane file managers, but intentionally keeps the first version simple: local files only, no cloud storage, no folder sync, and no remote connections yet.

## Screenshots

Screenshots will be added for the initial GitHub release.

- Main dual-pane window
- Conflict handling dialog
- Batch rename dialog

## Current MVP Features

- Dual-pane browsing
- Per-pane tabs
- Local file browsing
- Copy and move between panes
- Conflict handling: cancel, skip, replace, and keep both
- Rename and batch rename
- New folder
- Move to Trash
- Favorites sidebar
- File icons
- Filename filtering/search within the current folder
- Recursive filename search
- Quick Look preview
- Reveal in Finder and Open with default app
- Basic operation status messages

## Safety

OpenPane uses macOS Move to Trash for deletion-style actions. It does not permanently delete files.

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

- Local files only.
- No SFTP or other remote file systems yet.
- No cloud storage integrations.
- No folder sync.
- No signed or notarized release package yet.
- Operation progress is status-only; byte-level progress is not implemented yet.
- Conflict handling is intentionally simple and applies one selected strategy to the operation.
- Recursive search is filename-based, not content search.
- Tabs are basic and session-only.

## Project Structure

- `OpenPane/Models`
- `OpenPane/Services`
- `OpenPane/ViewModels`
- `OpenPane/Views`
- `OpenPane/Utilities`

## Keyboard Shortcuts

- `Command-R`: Refresh active pane
- `Command-Shift-R`: Refresh both panes
- `Command-Up`: Go up in the active pane
- `Command-Option-C`: Copy selection to the other pane
- `Command-Option-M`: Move selection to the other pane
- `Command-Shift-N`: New folder
- `Return`: Rename selected item
- `Command-Delete`: Move selection to Trash

## Roadmap

- SFTP support later
- Signed release builds
- Better operation progress
- Persistent user favorites
- More advanced conflict review
- File content search

## License

OpenPane is released under the MIT License. See [LICENSE](LICENSE).
