import Foundation

/// Where Home Assistant lives. The address is typed on the setup screen, so a bare `host:port`
/// is accepted and means plain http.
public struct HomeServer: Hashable, Sendable, Codable {
    public let baseURL: URL

    public init?(address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let text = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty else { return nil }
        parts.scheme = scheme
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { return nil }
        baseURL = url
    }

    /// `ws` or `wss` at `/api/websocket`.
    public var webSocketURL: URL {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.path = "/api/websocket"
        return parts.url!
    }

    public var address: String { baseURL.absoluteString }
}

public enum HomeConnection: Hashable, Sendable {
    /// No server address or token yet.
    case notConfigured
    case connecting
    case connected(version: String)
    /// The token was rejected. No retries until the address or token changes.
    case authFailed
    /// Lost or never reached; `retryAt` is when the next attempt starts.
    case disconnected(since: Date, retryAt: Date?)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Why the setup screen's connection test failed.
public enum HomeSetupError: Error, Hashable, Sendable {
    case badAddress
    case unreachable
    case invalidToken
    case timeout
    case unexpectedReply(String)
}

/// What a successful connection test found.
public struct HomeServerInfo: Hashable, Sendable {
    public let version: String
    public let entityCount: Int

    public init(version: String, entityCount: Int) {
        self.version = version
        self.entityCount = entityCount
    }
}
