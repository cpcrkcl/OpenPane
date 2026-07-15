//
//  NetworkPageView.swift
//  OpenPane
//

import SwiftUI

struct NetworkPageView: View {
    @StateObject private var viewModel: NetworkPageViewModel
    let onMount: ([URL]) -> Void

    @State private var connectionDraft: NetworkConnectionDraft?
    @State private var mountPoints: [URL] = []
    @State private var pendingMountURLs: [URL]?

    init(
        onMount: @escaping ([URL]) -> Void = { _ in },
        discoveryService: any NetworkDiscovering = NetworkDiscoveryService(),
        mountService: any NetworkMounting = NetworkMountService(),
        bookmarkStore: any NetworkServerBookmarkStoring = NetworkServerBookmarkStore()
    ) {
        self.onMount = onMount
        _viewModel = StateObject(
            wrappedValue: NetworkPageViewModel(
                discoveryService: discoveryService,
                mountService: mountService,
                bookmarkStore: bookmarkStore
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let statusMessage = viewModel.statusMessage {
                        statusBanner(statusMessage)
                    }

                    nearbyServersSection
                    savedServersSection
                    explanation
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .background(CatppuccinMochaTheme.base)
            .clipShape(RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium))
        }
        .padding(10)
        .background(CatppuccinMochaTheme.windowBackground)
        .accessibilityIdentifier("network-page")
        .task {
            viewModel.startBrowsing()
        }
        .onDisappear {
            viewModel.stopBrowsing()
        }
        .sheet(item: $connectionDraft, onDismiss: finishPendingMount) { draft in
            NetworkConnectToServerView(
                initialAddress: draft.address,
                initialDisplayName: draft.displayName
            ) { address, displayName, remember in
                let result = await viewModel.connect(
                    address: address,
                    displayName: displayName,
                    remember: remember
                )

                if case .success(let urls) = result {
                    pendingMountURLs = urls
                    connectionDraft = nil
                    viewModel.messageAfterMount(with: urls)
                }

                return result
            }
        }
        .sheet(isPresented: Binding(
            get: { !mountPoints.isEmpty },
            set: { isPresented in
                if !isPresented {
                    mountPoints = []
                }
            }
        )) {
            NetworkMountPointPickerView(mountPoints: mountPoints) { url in
                mountPoints = []
                onMount([url])
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .foregroundStyle(CatppuccinMochaTheme.teal)

            Text("Network")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)

            Spacer()

            Button {
                viewModel.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .accessibilityIdentifier("network-refresh")

            Button {
                presentConnectSheet()
            } label: {
                Label("Connect to Server…", systemImage: "server.rack")
            }
            .buttonStyle(SecondaryActionButtonStyle())
            .accessibilityIdentifier("connect-to-server-button")
        }
    }

    private var nearbyServersSection: some View {
        networkSection(title: "Nearby SMB Servers", systemImage: "dot.radiowaves.left.and.right") {
            if viewModel.isBrowsing && viewModel.discoveredServers.isEmpty {
                ProgressView("Looking for nearby SMB servers…")
                    .controlSize(.small)
                    .tint(CatppuccinMochaTheme.accent)
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            } else if viewModel.discoveredServers.isEmpty {
                Text("No advertised SMB servers were found nearby.")
                    .font(.system(size: 12))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
                    .accessibilityIdentifier("network-empty-state")
            } else {
                ForEach(viewModel.discoveredServers) { server in
                    NetworkServerRow(
                        title: server.displayName,
                        subtitle: server.serviceDescription,
                        systemImage: "externaldrive.connected.to.line.below"
                    ) {
                        connectionDraft = NetworkConnectionDraft(
                            address: server.serverURL?.absoluteString ?? "",
                            displayName: server.displayName
                        )
                    }
                }
            }
        }
    }

    private var savedServersSection: some View {
        networkSection(title: "Saved Servers", systemImage: "bookmark") {
            if viewModel.savedServers.isEmpty {
                Text("Saved SMB addresses will appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(CatppuccinMochaTheme.secondaryText)
            } else {
                ForEach(viewModel.savedServers) { server in
                    NetworkServerRow(
                        title: server.displayName,
                        subtitle: server.serverURL.absoluteString,
                        systemImage: "server.rack"
                    ) {
                        connectionDraft = NetworkConnectionDraft(
                            address: server.serverURL.absoluteString,
                            displayName: server.displayName
                        )
                    }
                    .contextMenu {
                        Button("Remove Saved Server", role: .destructive) {
                            viewModel.removeSavedServer(server)
                        }
                    }
                }
            }
        }
    }

    private var explanation: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(CatppuccinMochaTheme.accentSecondary)

            Text("Discovery is limited to SMB services advertised on the local network. For Tailscale, connect using a MagicDNS hostname or 100.x address, such as smb://server.example.ts.net/share.")
                .font(.system(size: 11))
                .foregroundStyle(CatppuccinMochaTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(CatppuccinMochaTheme.mantle, in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium))
    }

    private func networkSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CatppuccinMochaTheme.mutedText)

            VStack(alignment: .leading, spacing: 4, content: content)
                .padding(8)
                .background(CatppuccinMochaTheme.mantle, in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium))
        }
    }

    private func presentConnectSheet() {
        connectionDraft = NetworkConnectionDraft(address: "smb://", displayName: "")
    }

    private func handleMountURLs(_ urls: [URL]) {
        guard !urls.isEmpty else {
            onMount([])
            return
        }

        if urls.count == 1 {
            onMount(urls)
        } else {
            mountPoints = urls
        }
    }

    private func finishPendingMount() {
        guard let urls = pendingMountURLs else {
            return
        }

        pendingMountURLs = nil
        handleMountURLs(urls)
    }
}

private struct NetworkConnectionDraft: Identifiable {
    let id = UUID()
    let address: String
    let displayName: String
}

private struct NetworkServerRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(CatppuccinMochaTheme.teal)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CatppuccinMochaTheme.primaryText)

                    Text(subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(CatppuccinMochaTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CatppuccinMochaTheme.mutedText)
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct NetworkConnectToServerView: View {
    @Environment(\.dismiss) private var dismiss

    let initialAddress: String
    let initialDisplayName: String
    let onConnect: (String, String, Bool) async -> NetworkConnectionResult

    @State private var address: String
    @State private var displayName: String
    @State private var remember = true
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var connectionTask: Task<Void, Never>?

    init(
        initialAddress: String,
        initialDisplayName: String,
        onConnect: @escaping (String, String, Bool) async -> NetworkConnectionResult
    ) {
        self.initialAddress = initialAddress
        self.initialDisplayName = initialDisplayName
        self.onConnect = onConnect
        _address = State(initialValue: initialAddress)
        _displayName = State(initialValue: initialDisplayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to Server")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)

            Text("Enter an SMB address, hostname, or IP address. macOS will handle authentication.")
                .font(.system(size: 12))
                .foregroundStyle(CatppuccinMochaTheme.secondaryText)

            TextField("smb://server/share", text: $address)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("server-address-field")

            TextField("Display name (optional)", text: $displayName)
                .textFieldStyle(.roundedBorder)

            Toggle("Remember this server", isOn: $remember)
                .toggleStyle(.checkbox)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(CatppuccinMochaTheme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    connectionTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    isConnecting = true
                    errorMessage = nil
                    connectionTask?.cancel()
                    connectionTask = Task { @MainActor in
                        let result = await onConnect(address, displayName, remember)
                        guard !Task.isCancelled else {
                            return
                        }

                        isConnecting = false
                        connectionTask = nil

                        if case .failure(let message) = result {
                            errorMessage = message
                        }
                    }
                } label: {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isConnecting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("connect-server-submit")
            }
        }
        .padding(22)
        .frame(width: 430)
        .background(CatppuccinMochaTheme.appBackground)
        .preferredColorScheme(.dark)
        .onDisappear {
            connectionTask?.cancel()
            connectionTask = nil
        }
    }
}

private struct NetworkMountPointPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let mountPoints: [URL]
    let onSelect: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose Mounted Share")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CatppuccinMochaTheme.primaryText)

            Text("The server returned more than one mounted share.")
                .font(.system(size: 12))
                .foregroundStyle(CatppuccinMochaTheme.secondaryText)

            List(mountPoints, id: \.self) { mountPoint in
                Button {
                    onSelect(mountPoint)
                    dismiss()
                } label: {
                    Label(mountPoint.path, systemImage: "externaldrive")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(width: 430, height: 300)
        .background(CatppuccinMochaTheme.appBackground)
        .preferredColorScheme(.dark)
    }
}

private func statusBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(CatppuccinMochaTheme.destructive)

        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(CatppuccinMochaTheme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(10)
    .background(CatppuccinMochaTheme.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusMedium))
}
