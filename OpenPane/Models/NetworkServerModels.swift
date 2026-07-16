//
//  NetworkServerModels.swift
//  OpenPane
//
//  Created by Codex on 7/11/26.
//

import Foundation

nonisolated enum NetworkServerAddressError: LocalizedError, Equatable, Sendable {
    case emptyAddress
    case invalidAddress(String)
    case unsupportedScheme(String)
    case missingHost
    case credentialsNotAllowed
    case unsupportedURLComponents

    var errorDescription: String? {
        switch self {
        case .emptyAddress:
            return "Enter a server address."
        case .invalidAddress(let address):
            return "\(address) is not a valid server address."
        case .unsupportedScheme(let scheme):
            return "The \(scheme) URL scheme is not supported. Use an SMB address."
        case .missingHost:
            return "The server address must include a hostname or IP address."
        case .credentialsNotAllowed:
            return "Usernames and passwords cannot be included in server addresses."
        case .unsupportedURLComponents:
            return "Server addresses cannot include queries or fragments."
        }
    }
}

/// Parsing and normalization for user-entered or discovered SMB addresses.
/// Credentials are rejected so they cannot leak into bookmarks, logs, or
/// NetFS URLs. Authentication is delegated to macOS.
nonisolated enum NetworkServerAddress {
    static let smbScheme = "smb"

    static func normalize(_ address: String) throws -> URL {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAddress.isEmpty else {
            throw NetworkServerAddressError.emptyAddress
        }

        let candidate: String
        if trimmedAddress.contains("://") {
            candidate = trimmedAddress
        } else {
            candidate = schemelessSMBURLString(trimmedAddress)
        }

        guard let url = URL(string: candidate) else {
            throw NetworkServerAddressError.invalidAddress(trimmedAddress)
        }

        return try normalize(url)
    }

    static func normalize(_ url: URL) throws -> URL {
        guard let scheme = url.scheme?.lowercased() else {
            throw NetworkServerAddressError.invalidAddress(url.absoluteString)
        }

        guard scheme == smbScheme else {
            throw NetworkServerAddressError.unsupportedScheme(scheme)
        }

        guard url.user == nil, url.password == nil else {
            throw NetworkServerAddressError.credentialsNotAllowed
        }

        guard let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            throw NetworkServerAddressError.missingHost
        }

        guard url.query == nil, url.fragment == nil else {
            throw NetworkServerAddressError.unsupportedURLComponents
        }

        var components = URLComponents()
        components.scheme = smbScheme
        let normalizedHost = host.lowercased()
        components.host = normalizedHost.contains(":")
            ? "[\(normalizedHost)]"
            : normalizedHost
        components.port = url.port

        var path = url.path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path == "/" ? "" : path

        guard let normalizedURL = components.url else {
            throw NetworkServerAddressError.invalidAddress(url.absoluteString)
        }

        return normalizedURL
    }

    /// URL requires IPv6 literals to be bracketed. Accept the same convenient
    /// bare-address form as hostnames and IPv4 addresses, including a share
    /// path, and add the brackets before Foundation parses the URL.
    private static func schemelessSMBURLString(_ address: String) -> String {
        let remainder = address.hasPrefix("//")
            ? String(address.dropFirst(2))
            : address
        let pathStart = remainder.firstIndex(of: "/") ?? remainder.endIndex
        let authority = remainder[..<pathStart]
        let path = remainder[pathStart...]
        let colonCount = authority.reduce(into: 0) { count, character in
            if character == ":" {
                count += 1
            }
        }
        let normalizedAuthority: String
        if colonCount > 1, !authority.hasPrefix("[") {
            normalizedAuthority = "[\(authority)]"
        } else {
            normalizedAuthority = String(authority)
        }

        return "\(smbScheme)://\(normalizedAuthority)\(path)"
    }

    static func suggestedURL(serviceName: String, domain: String) -> URL? {
        let name = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDomain = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        guard !name.isEmpty, !normalizedDomain.isEmpty else {
            return nil
        }

        let hostLabel = name.unicodeScalars.map { scalar in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" {
                return String(scalar)
            }

            return "-"
        }
        .joined()
        .replacingOccurrences(of: "--", with: "-")
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        guard !hostLabel.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = smbScheme
        components.host = "\(hostLabel).\(normalizedDomain)"

        guard let url = components.url else {
            return nil
        }

        return try? normalize(url)
    }
}

/// A transient SMB service discovered through Bonjour.
nonisolated struct DiscoveredNetworkServer: Identifiable, Equatable, Hashable, Sendable {
    let name: String
    let serviceType: String
    let domain: String
    let suggestedServerURL: URL?

    init(
        name: String,
        serviceType: String = "_smb._tcp",
        domain: String = "local",
        suggestedServerURL: URL? = nil
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedServiceType = serviceType.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDomain = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        self.name = trimmedName
        self.serviceType = trimmedServiceType
        self.domain = trimmedDomain

        if let suggestedServerURL {
            self.suggestedServerURL = try? NetworkServerAddress.normalize(suggestedServerURL)
        } else if trimmedServiceType.caseInsensitiveCompare("_smb._tcp") == .orderedSame {
            self.suggestedServerURL = NetworkServerAddress.suggestedURL(
                serviceName: trimmedName,
                domain: trimmedDomain
            )
        } else {
            self.suggestedServerURL = nil
        }
    }

    var id: String {
        [name, serviceType, domain]
            .map { $0.lowercased() }
            .joined(separator: "|")
    }

    var displayName: String {
        name
    }

    var serverURL: URL? {
        suggestedServerURL
    }

    var serviceDescription: String {
        "\(serviceType) • \(domain)"
    }
}

/// A user-saved SMB address. The initializer and decoder both validate the
/// URL, ensuring credentials can never be stored in this model.
nonisolated struct NetworkServerBookmark: Identifiable, Codable, Equatable, Hashable, Sendable {
    let displayName: String
    let serverURL: URL

    init(displayName: String, serverURL: URL) throws {
        let normalizedURL = try NetworkServerAddress.normalize(serverURL)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        self.displayName = trimmedDisplayName.isEmpty
            ? (normalizedURL.host ?? normalizedURL.absoluteString)
            : trimmedDisplayName
        self.serverURL = normalizedURL
    }

    init(displayName: String, address: String) throws {
        try self.init(
            displayName: displayName,
            serverURL: NetworkServerAddress.normalize(address)
        )
    }

    var id: String {
        serverURL.absoluteString
    }

    var name: String {
        displayName
    }

    var url: URL {
        serverURL
    }

    private enum CodingKeys: String, CodingKey {
        case displayName
        case serverURL
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            displayName: container.decode(String.self, forKey: .displayName),
            serverURL: container.decode(URL.self, forKey: .serverURL)
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(serverURL, forKey: .serverURL)
    }
}
