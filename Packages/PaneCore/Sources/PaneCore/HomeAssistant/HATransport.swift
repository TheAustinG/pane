import Foundation

/// One WebSocket connection carrying Home Assistant's JSON text frames.
public protocol HATransport: Sendable {
    func send(_ text: String) async throws
    /// The next text frame. Throws when the socket closes or fails.
    func receive() async throws -> String
    func close()
}

/// Opens connections, so tests and fixture runs can swap in a scripted server.
public protocol HATransportFactory: Sendable {
    func connect(to url: URL) -> any HATransport
}

/// Delay before each reconnect attempt: doubling from `initial`, capped at `maximum`, with up to
/// `jitter` of the delay added at random so a restarted server is not hit by every client at once.
public struct ReconnectBackoff: Hashable, Sendable {
    public var initial: TimeInterval
    public var maximum: TimeInterval
    public var jitter: Double

    public init(initial: TimeInterval = 1, maximum: TimeInterval = 30, jitter: Double = 0.2) {
        self.initial = initial
        self.maximum = maximum
        self.jitter = jitter
    }

    /// `attempt` counts failures since the last good connection, from 0.
    public func delay(attempt: Int, random: Double = .random(in: 0...1)) -> TimeInterval {
        let base = min(maximum, initial * pow(2, Double(max(attempt, 0))))
        return min(maximum, base + base * jitter * random)
    }
}

/// `URLSessionWebSocketTask` connections.
public struct URLSessionHATransportFactory: HATransportFactory {
    public init() {}

    public func connect(to url: URL) -> any HATransport {
        URLSessionHATransport(url: url)
    }
}

final class URLSessionHATransport: HATransport, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(url: URL) {
        task = URLSession.shared.webSocketTask(with: url)
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: throw URLError(.cannotParseResponse)
        }
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}
