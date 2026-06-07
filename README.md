# OpenPane

OpenPane is a local-first, open-source native macOS dual-pane file manager.

The MVP is focused on fast, practical local file browsing and basic file operations. It is inspired by classic dual-pane file managers, but intentionally keeps the first version simple: local files only, no cloud storage, no folder sync, no tabs, and no remote connections yet.

## Current MVP Features

- Dual-pane browsing
- Local file browsing
- Copy and move between panes
- Rename
- New folder
- Move to Trash
- Favorites sidebar
- File icons
- Filename filtering/search within the current folder
- Quick Look preview

## Safety

OpenPane uses macOS Move to Trash for deletion-style actions. It does not permanently delete files.

## Requirements

- macOS 14+
- Xcode
- Swift
- SwiftUI
- XCTest / Swift Testing

## Build And Run

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

- Tabs
- Better conflict handling
- Recursive search
- Batch rename
- SFTP support later

## License

OpenPane is intended to be released as open source. A license file has not been added yet.
