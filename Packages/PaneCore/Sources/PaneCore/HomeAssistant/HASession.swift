import Foundation

/// One WebSocket connection to Home Assistant: authentication, requests matched to their results by
/// id, and `state_changed` events handed to `onEvent`. Frames are read and decoded off the main actor.
@MainActor
final class HASession {
    enum Failure: Error, Hashable {
        case closed
        case timeout
        case authInvalid
        case unexpectedReply(String)
        case rejected(HAErrorInfo)
    }

    private struct Pending {
        let continuation: CheckedContinuation<HAResultPayload?, any Error>
        let timer: Task<Void, Never>
    }

    let transport: any HATransport
    private let clock: any WeatherClock
    private var nextID = 1
    private var pending: [Int: Pending] = [:]
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    private let outbox: AsyncStream<String>.Continuation
    private let outgoing: AsyncStream<String>
    private var reader: Task<Void, Never>?
    private var writer: Task<Void, Never>?
    /// Frames read since `start()`, so the heartbeat can tell a live socket from a dead one.
    private(set) var framesReceived = 0
    private(set) var isClosed = false
    var onEvent: ((HAStateChange) -> Void)?

    init(transport: any HATransport, clock: any WeatherClock) {
        self.transport = transport
        self.clock = clock
        (outgoing, outbox) = AsyncStream.makeStream(of: String.self)
    }

    /// Answers `auth_required` with the token and returns the server's version from `auth_ok`.
    func authenticate(token: String, until deadline: Date) async throws -> String {
        guard case .authRequired = try await receiveBeforeStart(until: deadline) else {
            throw Failure.unexpectedReply("The server did not ask for authentication")
        }
        let message = HAOutbound.auth(token: token)
        let transport = transport
        try await within(deadline) { try await transport.send(message) }
        switch try await receiveBeforeStart(until: deadline) {
        case .authOK(let version): return version ?? "unknown"
        case .authInvalid: throw Failure.authInvalid
        default: throw Failure.unexpectedReply("The server did not answer authentication")
        }
    }

    /// Starts reading frames and sending queued messages. Call once, after `authenticate`.
    func start() {
        guard reader == nil, !isClosed else { return }
        let transport = transport
        let outgoing = outgoing
        // One writer keeps frames in id order: Home Assistant rejects an id lower than one it has seen.
        writer = Task { [weak self] in
            for await text in outgoing {
                do {
                    try await transport.send(text)
                } catch {
                    self?.close()
                    return
                }
            }
        }
        reader = Task { [weak self] in
            while true {
                let frame: HAInbound
                do {
                    frame = try await Self.nextFrame(from: transport)
                } catch {
                    self?.close()
                    return
                }
                guard let self, !self.isClosed else { return }
                self.handle(frame)
            }
        }
    }

    /// Sends a command built with the next id and waits for its `result`.
    func request(_ message: (Int) -> String, until deadline: Date) async throws -> HAResultPayload? {
        guard !isClosed else { throw Failure.closed }
        let id = takeID()
        let text = message(id)
        let clock = clock
        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task { [weak self] in
                do {
                    try await clock.sleep(until: deadline)
                } catch {
                    return
                }
                self?.resolve(id, with: .failure(Failure.timeout))
            }
            pending[id] = Pending(continuation: continuation, timer: timer)
            outbox.yield(text)
        }
    }

    /// Sends a command built with the next id without waiting for an answer.
    func send(_ message: (Int) -> String) {
        guard !isClosed else { return }
        outbox.yield(message(takeID()))
    }

    func waitUntilClosed() async {
        guard !isClosed else { return }
        await withCheckedContinuation { closeWaiters.append($0) }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        transport.close()
        outbox.finish()
        let waiting = pending
        pending = [:]
        for entry in waiting.values {
            entry.timer.cancel()
            entry.continuation.resume(throwing: Failure.closed)
        }
        let waiters = closeWaiters
        closeWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func handle(_ frame: HAInbound) {
        framesReceived += 1
        switch frame {
        case .result(let id, let reply):
            resolve(id, with: reply.mapError { Failure.rejected($0) })
        case .event(_, let change?):
            onEvent?(change)
        default:
            break
        }
    }

    private func resolve(_ id: Int, with result: Result<HAResultPayload?, Failure>) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timer.cancel()
        entry.continuation.resume(with: result.mapError { $0 as any Error })
    }

    private func receiveBeforeStart(until deadline: Date) async throws -> HAInbound {
        guard !isClosed else { throw Failure.closed }
        let transport = transport
        return try await within(deadline) { try await Self.nextFrame(from: transport) }
    }

    /// Runs `operation` until `deadline`. On timeout the socket is closed, which also ends an
    /// operation that ignores cancellation.
    private func within<T: Sendable>(_ deadline: Date, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let clock = clock
        let transport = transport
        do {
            return try await withThrowingTaskGroup(of: T?.self) { group in
                group.addTask { try await operation() }
                group.addTask {
                    try await clock.sleep(until: deadline)
                    return nil
                }
                defer { group.cancelAll() }
                guard let value = try await group.next() ?? nil else {
                    transport.close()
                    throw Failure.timeout
                }
                return value
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.closed
        }
    }

    @concurrent
    private nonisolated static func nextFrame(from transport: any HATransport) async throws -> HAInbound {
        HAInbound.decode(try await transport.receive())
    }
}
