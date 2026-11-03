import Foundation
import Synchronization

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
    /// Phase 0 measured `get_states` on a real install well past the 1 MB default.
    static let maximumMessageSize = 32 * 1024 * 1024

    private let task: URLSessionWebSocketTask
    private let closed = Mutex(false)

    init(url: URL, session: URLSession = .shared) {
        task = session.webSocketTask(with: url)
        task.maximumMessageSize = Self.maximumMessageSize
        task.resume()
    }

    func send(_ text: String) async throws {
        guard !isClosed else { throw URLError(.networkConnectionLost) }
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        guard !isClosed else { throw URLError(.networkConnectionLost) }
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data): return String(decoding: data, as: UTF8.self)
        @unknown default: throw URLError(.cannotParseResponse)
        }
    }

    func close() {
        let wasOpen = closed.withLock { closed in
            defer { closed = true }
            return !closed
        }
        guard wasOpen else { return }
        task.cancel(with: .normalClosure, reason: nil)
    }

    var maximumMessageSize: Int {
        task.maximumMessageSize
    }

    private var isClosed: Bool {
        closed.withLock { $0 }
    }
}
