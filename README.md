# OpenPane

OpenPane is a free, open-source, local-first macOS dual-pane file manager MVP.

The initial goal is a native Swift and SwiftUI app for browsing and managing local files on macOS. The MVP intentionally focuses on local files only, without SFTP, cloud storage, folder sync, or tabs.

## Project Structure

- `OpenPane/Models`
- `OpenPane/Services`
- `OpenPane/ViewModels`
- `OpenPane/Views`
- `OpenPane/Utilities`

## Requirements

- macOS 14+
- Swift
- SwiftUI
- XCTest / Swift Testing

## Keyboard Shortcuts

- `Command-R`: Refresh active pane
- `Command-Shift-R`: Refresh both panes
- `Command-Up`: Go up in the active pane
- `Command-Option-C`: Copy selection to the other pane
- `Command-Option-M`: Move selection to the other pane
- `Command-Shift-N`: New folder
- `Return`: Rename selected item
- `Command-Delete`: Move selection to Trash
