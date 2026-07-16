//
//  PreviewPanelView.swift
//  OpenPane
//

import AppKit
import SwiftUI

struct PreviewPanelView: View {
    @ObservedObject var viewModel: PreviewPanelViewModel

    let onClose: () -> Void
    let onOpen: (URL) -> Void
    let onFullQuickLook: (URL) -> Void
    let onSaved: @MainActor @Sendable (URL) -> Void
    let onCancelClose: () -> Void

    init(
        viewModel: PreviewPanelViewModel,
        onClose: @escaping () -> Void,
        onOpen: @escaping (URL) -> Void,
        onFullQuickLook: @escaping (URL) -> Void,
        onSaved: @escaping @MainActor @Sendable (URL) -> Void = { _ in },
        onCancelClose: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.onOpen = onOpen
        self.onFullQuickLook = onFullQuickLook
        self.onSaved = onSaved
        self.onCancelClose = onCancelClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(CatppuccinMochaTheme.surface1)

            if viewModel.isEditing, let buffer = viewModel.editorBuffer {
                editor(buffer: buffer)
            } else if let target = viewModel.target {
                previewAndDetails(target: target)
            } else {
                emptyState
            }

            Divider().overlay(CatppuccinMochaTheme.surface1)
            actionBar
        }
        .background(CatppuccinMochaTheme.paneBackground)
        .confirmationDialog(
            confirmationTitle,
            isPresented: promptIsPresented,
            titleVisibility: .visible
        ) {
            confirmationActions
        } message: {
            Text(confirmationMessage)
        }
        .alert("Preview Error", isPresented: errorIsPresented) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "The preview could not be updated.")
        }
        .onChange(of: viewModel.resolvedCloseRequestCount) { _, _ in
            onClose()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = viewModel.icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: viewModel.target?.item.isDirectory == true ? "folder.fill" : "doc")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(
                            viewModel.target?.item.isDirectory == true
                                ? CatppuccinMochaTheme.lavender
                                : CatppuccinMochaTheme.mutedText
                        )
                }
            }
            .scaledToFit()
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Preview")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(CatppuccinMochaTheme.mutedText)

                Text(viewModel.target?.item.displayName ?? "No Selection")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CatppuccinMochaTheme.primaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button {
                if viewModel.requestClose() {
                    onClose()
                }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("Hide Preview Panel")
            .accessibilityLabel("Hide Preview Panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func previewAndDetails(target: FilePreviewTarget) -> some View {
        GeometryReader { proxy in
            let previewHeight = min(420, max(220, proxy.size.height * 0.4))

            VStack(spacing: 0) {
                previewArea(target: target)
                    .frame(height: previewHeight)

                Divider().overlay(CatppuccinMochaTheme.surface1)

                detailsInspector(target: target)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func previewArea(target: FilePreviewTarget) -> some View {
        let metadataOnly = target.item.isDirectory ||
            viewModel.metadata?.isDirectory == true ||
            viewModel.metadata?.isPackage == true

        if metadataOnly {
            VStack(spacing: 10) {
                if let icon = viewModel.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                } else {
                    Image(systemName: target.item.isDirectory ? "folder.fill" : "shippingbox.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(CatppuccinMochaTheme.lavender)
                }

                Text(viewModel.metadata?.kindDescription ?? target.item.kindDescription)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CatppuccinMochaTheme.base)
        } else if VideoPreviewPolicy.isVideo(
            typeIdentifier: viewModel.metadata?.typeIdentifier ?? target.item.typeIdentifier,
            fileExtension: target.item.url.pathExtension
        ) {
            VideoThumbnailView(
                url: target.item.url,
                revision: viewModel.previewRevision ?? FilePreviewRevision(
                    resourceIdentifier: nil,
                    logicalSize: target.item.size,
                    contentModificationDate: target.item.modifiedDate
                )
            )
        } else {
            QuickLookPreviewView(
                url: target.item.url,
                revision: viewModel.previewRevision ?? FilePreviewRevision(
                    resourceIdentifier: nil,
                    logicalSize: target.item.size,
                    contentModificationDate: target.item.modifiedDate
                )
            )
            .id(target.id)
            .background(CatppuccinMochaTheme.base)
        }
    }

    private func detailsInspector(target: FilePreviewTarget) -> some View {
        LightweightPreviewDetailsView(
            targetID: target.id,
            sections: detailSections(for: target),
            isLoading: viewModel.metadata == nil && viewModel.isLoadingMetadata
        )
        .id(target.id)
        .background(CatppuccinMochaTheme.paneBackground)
    }

    private func detailSections(for target: FilePreviewTarget) -> [PreviewDetailSection] {
        guard let metadata = viewModel.metadata else {
            guard !viewModel.isLoadingMetadata else { return [] }
            return [
                PreviewDetailSection(title: "General", rows: [
                    detailRow("Name", target.item.displayName, selectable: true),
                    detailRow("Kind", target.item.kindDescription),
                    detailRow("Size", target.item.isDirectory ? "Folder" : target.item.formattedSize),
                    detailRow(
                        "Modified",
                        target.item.formattedModifiedDate.isEmpty ? "—" : target.item.formattedModifiedDate
                    ),
                    detailRow("Path", target.item.url.path, selectable: true, allowsWrapping: true)
                ])
            ]
        }

        var generalRows = [
            detailRow("Name", metadata.name, selectable: true),
            detailRow("Kind", metadata.kindDescription),
            detailRow("Extension", display(metadata.fileExtension)),
            detailRow("Type", display(metadata.typeIdentifier), selectable: true),
            detailRow("MIME", display(metadata.mimeType), selectable: true),
            detailRow("Path", metadata.fullPath, selectable: true, allowsWrapping: true),
            detailRow("Parent", metadata.parentPath, selectable: true, allowsWrapping: true),
            detailRow("Volume", display(metadata.volumeName)),
            detailRow("Location", volumeDescription(metadata.volumeKind))
        ]
        if let symbolicLinkTarget = metadata.symbolicLinkTarget {
            generalRows.append(
                detailRow("Link Target", symbolicLinkTarget, selectable: true, allowsWrapping: true)
            )
        }

        let sizeRows: [PreviewDetailRow]
        if metadata.isDirectory || metadata.isPackage {
            sizeRows = [detailRow("Logical", metadata.isPackage ? "Package" : "Folder")]
        } else {
            sizeRows = [
                detailRow("Logical", formatBytes(metadata.logicalSize)),
                detailRow("On Disk", formatBytes(metadata.allocatedSize))
            ]
        }

        var sections = [
            PreviewDetailSection(title: "General", rows: generalRows),
            PreviewDetailSection(title: "Dates", rows: [
                detailRow("Created", format(metadata.creationDate)),
                detailRow("Modified", format(metadata.contentModificationDate)),
                detailRow("Metadata Changed", format(metadata.attributeModificationDate)),
                detailRow("Last Opened", format(metadata.contentAccessDate)),
                detailRow("Added", format(metadata.addedToDirectoryDate))
            ]),
            PreviewDetailSection(title: "Size", rows: sizeRows),
            PreviewDetailSection(title: "Access", rows: [
                detailRow("Owner", display(metadata.ownerAccountName)),
                detailRow("Group", display(metadata.groupOwnerAccountName)),
                detailRow("Permissions", display(metadata.permissionsDescription), selectable: true),
                detailRow("Readable", format(metadata.isReadable)),
                detailRow("Writable", format(metadata.isWritable)),
                detailRow("Executable", format(metadata.isExecutable)),
                detailRow(
                    "Finder Tags",
                    metadata.finderTags.isEmpty ? "—" : metadata.finderTags.joined(separator: ", ")
                )
            ])
        ]

        if let formatDetails = metadata.formatDetails {
            sections.append(formatDetailSection(formatDetails))
        } else if let encoding = viewModel.inspectedTextEncoding {
            sections.append(
                PreviewDetailSection(title: "Text", rows: [
                    detailRow("Encoding", encoding.displayName),
                    detailRow("Byte Order Mark", encoding.hasByteOrderMark ? "Yes" : "No")
                ])
            )
        }
        return sections
    }

    private func formatDetailSection(_ details: FileFormatDetails) -> PreviewDetailSection {
        switch details {
        case .image(let pixelWidth, let pixelHeight, let colorModel):
            PreviewDetailSection(title: "Image", rows: [
                detailRow("Dimensions", "\(pixelWidth) × \(pixelHeight) pixels"),
                detailRow("Color Model", display(colorModel))
            ])
        case .pdf(let pageCount, let isEncrypted):
            PreviewDetailSection(title: "PDF", rows: [
                detailRow("Pages", pageCount.formatted()),
                detailRow("Encrypted", isEncrypted ? "Yes" : "No")
            ])
        case .audio(let duration):
            PreviewDetailSection(title: "Audio", rows: [
                detailRow("Duration", formatDuration(duration))
            ])
        case .video(let duration, let pixelWidth, let pixelHeight):
            PreviewDetailSection(title: "Video", rows: [
                detailRow("Duration", formatDuration(duration)),
                detailRow(
                    "Resolution",
                    pixelWidth.flatMap { width in pixelHeight.map { "\(width) × \($0)" } } ?? "—"
                )
            ])
        case .application(let bundleIdentifier, let shortVersion, let buildVersion):
            PreviewDetailSection(title: "Application", rows: [
                detailRow("Bundle ID", display(bundleIdentifier), selectable: true),
                detailRow("Version", display(shortVersion)),
                detailRow("Build", display(buildVersion))
            ])
        case .text(let encoding, let hasByteOrderMark):
            PreviewDetailSection(title: "Text", rows: [
                detailRow("Encoding", encoding),
                detailRow("Byte Order Mark", hasByteOrderMark ? "Yes" : "No")
            ])
        }
    }

    private func editor(buffer: PlainTextEditorBuffer) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let document = viewModel.editableDocument {
                    Text(document.encoding.displayName)
                    if document.encoding.hasByteOrderMark {
                        Text("BOM")
                    }
                }
                Spacer()
                if viewModel.isDirty {
                    Text("Edited")
                        .foregroundStyle(CatppuccinMochaTheme.warning)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(CatppuccinMochaTheme.mutedText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(CatppuccinMochaTheme.mantle)

            PlainTextEditorView(buffer: buffer, isEditable: !viewModel.isSaving)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(CatppuccinMochaTheme.mutedText)
            Text("Select a file to preview")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            Text("Details and supported previews appear here.")
                .font(.system(size: 11))
                .foregroundStyle(CatppuccinMochaTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack(spacing: 7) {
            if viewModel.isEditing {
                Button {
                    viewModel.cancelEditing()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(viewModel.isSaving)

                Spacer(minLength: 0)

                Button {
                    viewModel.save { @MainActor @Sendable url in
                        onSaved(url)
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!viewModel.isDirty || viewModel.isSaving)
            } else if let target = viewModel.target {
                Button {
                    onOpen(target.item.url)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(SecondaryActionButtonStyle())

                Button {
                    onFullQuickLook(target.item.url)
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(target.item.isDirectory)

                Spacer(minLength: 0)

                if viewModel.isLoadingText {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else if viewModel.canBeginEditing {
                    Button {
                        viewModel.beginEditing()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CatppuccinMochaTheme.mantle)
    }

    private func detailRow(
        _ title: String,
        _ value: String,
        selectable: Bool = false,
        allowsWrapping: Bool = false
    ) -> PreviewDetailRow {
        PreviewDetailRow(
            title: title,
            value: value,
            isSelectable: selectable,
            allowsWrapping: allowsWrapping
        )
    }

    @ViewBuilder
    private var confirmationActions: some View {
        switch viewModel.unsavedChangesPrompt {
        case .transition:
            Button("Save") {
                viewModel.save { @MainActor @Sendable url in
                    onSaved(url)
                }
            }
            Button("Discard Changes", role: .destructive) {
                viewModel.discardChanges()
            }
            Button("Cancel", role: .cancel) {
                viewModel.keepEditing()
                onCancelClose()
            }
        case .conflict:
            Button("Reload", role: .destructive) {
                viewModel.reloadChangedFile()
            }
            Button("Overwrite") {
                viewModel.overwriteChangedFile { @MainActor @Sendable url in
                    onSaved(url)
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.keepEditing()
                onCancelClose()
            }
        case nil:
            EmptyView()
        }
    }

    private var promptIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.unsavedChangesPrompt != nil },
            set: { isPresented in
                if !isPresented, viewModel.unsavedChangesPrompt != nil {
                    viewModel.keepEditing()
                    onCancelClose()
                }
            }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private var confirmationTitle: String {
        switch viewModel.unsavedChangesPrompt {
        case .transition:
            return "Save Changes?"
        case .conflict:
            return "File Changed"
        case nil:
            return ""
        }
    }

    private var confirmationMessage: String {
        switch viewModel.unsavedChangesPrompt {
        case .transition:
            return "Save your edits before leaving this file?"
        case .conflict:
            return "The file changed after it was opened. Reload it, overwrite the newer version, or keep editing."
        case nil:
            return ""
        }
    }

    private func display(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "—"
        }
        return value
    }

    private func format(_ date: Date?) -> String {
        guard let date else {
            return "—"
        }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private func format(_ value: Bool?) -> String {
        guard let value else {
            return "—"
        }
        return value ? "Yes" : "No"
    }

    private func formatBytes(_ byteCount: Int64?) -> String {
        guard let byteCount else {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func formatDuration(_ duration: TimeInterval?) -> String {
        guard let duration, duration.isFinite, duration >= 0 else {
            return "—"
        }
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func volumeDescription(_ kind: FilePreviewVolumeKind) -> String {
        switch kind {
        case .local:
            return "Local volume"
        case .network:
            return "Network-mounted volume"
        case .unknown:
            return "Unknown"
        }
    }
}
