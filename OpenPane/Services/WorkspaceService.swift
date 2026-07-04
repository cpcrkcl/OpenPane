//
//  WorkspaceService.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/5/26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct ApplicationOption: Identifiable {
    let name: String
    let url: URL
    let icon: NSImage?

    var id: URL {
        url
    }
}

enum WorkspaceError: LocalizedError {
    case noShareItems
    case sharingUnavailable
    case openFailed(URL)
    case openWithApplicationFailed(URL, URL, String)

    var errorDescription: String? {
        switch self {
        case .noShareItems:
            return "Select one or more items to share."
        case .sharingUnavailable:
            return "Sharing is not available right now."
        case .openFailed(let url):
            return "Could not open \(url.openPaneDisplayName)."
        case .openWithApplicationFailed(let url, let applicationURL, let reason):
            return "Could not open \(url.openPaneDisplayName) with \(Self.applicationName(for: applicationURL)): \(reason)"
        }
    }

    private static func applicationName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? url.openPaneDisplayName : name
    }
}

nonisolated protocol WorkspaceServicing: Sendable {
    @MainActor
    @discardableResult
    func open(url: URL) -> Bool

    @MainActor
    func appsAvailableToOpen(url: URL) -> [ApplicationOption]

    @MainActor
    func open(url: URL, withApplication applicationURL: URL) async throws

    @MainActor
    func chooseApplicationAndOpen(url: URL)

    @MainActor
    func revealInFinder(urls: [URL])

    @MainActor
    func share(urls: [URL]) throws

    @MainActor
    func copyFileURLs(_ urls: [URL])

    @MainActor
    func fileURLsForPasteboard() -> [URL]

    @MainActor
    func copyPath(url: URL)

    @MainActor
    func copyText(_ text: String)
}

nonisolated struct WorkspaceService: WorkspaceServicing {
    nonisolated init() {}

    @MainActor
    @discardableResult
    func open(url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    func appsAvailableToOpen(url: URL) -> [ApplicationOption] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
            .reduce(into: [URL]()) { urls, applicationURL in
                guard !urls.contains(applicationURL) else {
                    return
                }

                urls.append(applicationURL)
            }
            .map { applicationURL in
                let icon = Self.resizedIconCopy(
                    NSWorkspace.shared.icon(forFile: applicationURL.path)
                )

                return ApplicationOption(
                    name: Self.applicationName(for: applicationURL),
                    url: applicationURL,
                    icon: icon
                )
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    @MainActor
    func open(url: URL, withApplication applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(
                        throwing: WorkspaceError.openWithApplicationFailed(
                            url,
                            applicationURL,
                            error.localizedDescription
                        )
                    )
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    func chooseApplicationAndOpen(url: URL) {
        let panel = NSOpenPanel()
        panel.title = "Choose Application"
        panel.prompt = "Open"
        panel.message = "Choose an application to open \(url.openPaneDisplayName)."
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK,
              let applicationURL = panel.url else {
            return
        }

        Task {
            try? await open(url: url, withApplication: applicationURL)
        }
    }

    @MainActor
    func revealInFinder(urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @MainActor
    func share(urls: [URL]) throws {
        guard !urls.isEmpty else {
            throw WorkspaceError.noShareItems
        }

        guard let contentView = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else {
            throw WorkspaceError.sharingUnavailable
        }

        let picker = NSSharingServicePicker(items: urls)
        let anchorRect = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY,
            width: 1,
            height: 1
        )

        picker.show(relativeTo: anchorRect, of: contentView, preferredEdge: .minY)
    }

    @MainActor
    func copyFileURLs(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    @MainActor
    func fileURLsForPasteboard() -> [URL] {
        let pasteboard = NSPasteboard.general
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []

        return objects.compactMap { object in
            if let url = object as? URL {
                return url
            }

            if let nsURL = object as? NSURL {
                return nsURL as URL
            }

            return nil
        }
    }

    @MainActor
    func copyPath(url: URL) {
        copyText(url.path)
    }

    @MainActor
    func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func applicationName(for url: URL) -> String {
        let resourceValues = try? url.resourceValues(forKeys: [.localizedNameKey])

        if let localizedName = resourceValues?.localizedName,
           !localizedName.isEmpty {
            return localizedName.replacingOccurrences(of: ".app", with: "")
        }

        return url.deletingPathExtension().lastPathComponent
    }

    private static func resizedIconCopy(_ image: NSImage) -> NSImage {
        let copiedImage = (image.copy() as? NSImage) ?? image
        copiedImage.size = NSSize(width: 16, height: 16)
        return copiedImage
    }
}
