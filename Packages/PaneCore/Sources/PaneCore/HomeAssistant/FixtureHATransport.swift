import Foundation
import Synchronization

/// An in-process Home Assistant for tests and fixture runs. It speaks the WebSocket JSON the real
/// server does: authentication, `get_states`, `subscribe_events`, `call_service` and `ping`.
/// Service calls are recorded; `input_boolean`, `light` and `switch` turn on, off and toggle, and
/// `script` and `scene` stamp `last_triggered`, each emitting `state_changed` like the real thing.
public final class FixtureHATransportFactory: HATransportFactory {
    /// The token `HomeController.preview` configures.
    public static let defaultToken = "fixture-token"
    public static let defaultVersion = "2026.10.0"

    public struct ServiceCall: Hashable, Sendable {
        public let domain: String
        public let service: String
        public let entityIDs: [String]

        public init(domain: String, service: String, entityIDs: [String]) {
            self.domain = domain
            self.service = service
            self.entityIDs = entityIDs
        }
    }

    struct Snapshot: Sendable {
        let connectionsOpened: Int
        let openConnections: Int
        /// Client frames in arrival order, with any token replaced.
        let received: [String]
        /// Every open connection has read all it was sent and is waiting for more.
        let isIdle: Bool
        let serviceCalls: [ServiceCall]
    }

    private struct Connection {
        var outbound: [String]
        var waiter: CheckedContinuation<String, any Error>?
        var authenticated = false
        var closesAfterDrain = false
        var lastID = 0
        var subscriptions: [Int] = []
    }

    private struct Watcher {
        let condition: @Sendable (Snapshot) -> Bool
        let continuation: CheckedContinuation<Void, Never>
    }

    private enum Effect: Sendable {
        case deliver(CheckedContinuation<String, any Error>, String)
        case fail(CheckedContinuation<String, any Error>, URLError.Code)
        case wake(CheckedContinuation<Void, Never>)
    }

    private struct State {
        var entities: [String: HAEntity]
        var version: String
        var expectedToken: String?
        var refusesConnections = false
        var respondsToPings = true
        var ignoresServiceCalls = false
        var failures: [String: (code: String, message: String)] = [:]
        var connections: [Int: Connection] = [:]
        var connectionsOpened = 0
        var serviceCalls: [ServiceCall] = []
        var received: [String] = []
        var contexts = 0
        var watchers: [Watcher] = []

        var snapshot: Snapshot {
            Snapshot(
                connectionsOpened: connectionsOpened,
                openConnections: connections.count,
                received: received,
                isIdle: connections.values.allSatisfy { $0.outbound.isEmpty && $0.waiter != nil },
                serviceCalls: serviceCalls
            )
        }
    }

    private static let switchable: Set<String> = ["input_boolean", "light", "switch"]

    private let state: Mutex<State>
    private let now: @Sendable () -> Date

    /// `expectedToken` nil accepts any non-empty token.
    public init(
        entities: [HAEntity] = [],
        version: String = defaultVersion,
        expectedToken: String? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        state = Mutex(State(
            entities: Dictionary(entities.map { ($0.entityID, $0) }, uniquingKeysWith: { _, last in last }),
            version: version,
            expectedToken: expectedToken
        ))
        self.now = now
    }

    public func connect(to url: URL) -> any HATransport {
        let id = mutate { state, _ -> Int? in
            state.connectionsOpened += 1
            guard !state.refusesConnections else { return nil }
            let id = state.connectionsOpened
            state.connections[id] = Connection(outbound: [Self.encode(["type": .string("auth_required"), "ha_version": .string(state.version)])])
            return id
        }
        return FixtureHATransport(server: self, connection: id)
    }

    public var entities: [HAEntity] {
        state.withLock { $0.entities.values.sorted { $0.entityID < $1.entityID } }
    }

    public func entity(_ entityID: String) -> HAEntity? {
        state.withLock { $0.entities[entityID] }
    }

    /// Sets a state, creating the entity if needed, and emits `state_changed`.
    public func setState(_ entityID: String, to newState: String, attributes: [String: HAValue]? = nil) {
        mutate { state, _ in
            let old = state.entities[entityID]
            var entity = old ?? HAEntity(entityID: entityID, state: newState)
            entity.state = newState
            if let attributes { entity.attributes = attributes }
            let stamp = now()
            if old?.state != newState || entity.lastChanged == nil { entity.lastChanged = stamp }
            entity.lastUpdated = stamp
            state.entities[entityID] = entity
            Self.broadcast(entityID: entityID, old: old, new: entity, at: stamp, in: &state)
        }
    }

    /// Replaces an entity whole and emits `state_changed`.
    public func setEntity(_ entity: HAEntity) {
        mutate { state, _ in
            let old = state.entities[entity.entityID]
            state.entities[entity.entityID] = entity
            Self.broadcast(entityID: entity.entityID, old: old, new: entity, at: now(), in: &state)
        }
    }

    /// Removes an entity and emits `state_changed` with a null `new_state`.
    public func removeEntity(_ entityID: String) {
        mutate { state, _ in
            guard let old = state.entities.removeValue(forKey: entityID) else { return }
            Self.broadcast(entityID: entityID, old: old, new: nil, at: now(), in: &state)
        }
    }

    public var serviceCalls: [ServiceCall] {
        state.withLock { $0.serviceCalls }
    }

    /// Connections opened so far, refused ones included.
    public var connectionsOpened: Int {
        state.withLock { $0.connectionsOpened }
    }

    /// Drops every open connection as if the network failed.
    public func dropConnections() {
        mutate { state, effects in
            for connection in state.connections.values {
                if let waiter = connection.waiter { effects.append(.fail(waiter, .networkConnectionLost)) }
            }
            state.connections = [:]
        }
    }

    /// New connections fail at once, like a server that is down.
    public var refusesConnections: Bool {
        get { state.withLock { $0.refusesConnections } }
        set { mutate { state, _ in state.refusesConnections = newValue } }
    }

    /// False leaves pings unanswered, like a socket that died without closing.
    public var respondsToPings: Bool {
        get { state.withLock { $0.respondsToPings } }
        set { mutate { state, _ in state.respondsToPings = newValue } }
    }

    /// True records service calls but never answers them.
    public var ignoresServiceCalls: Bool {
        get { state.withLock { $0.ignoresServiceCalls } }
        set { mutate { state, _ in state.ignoresServiceCalls = newValue } }
    }

    /// Answers calls to `domain.service` with `success: false` and this error.
    public func failCalls(to domain: String, _ service: String, code: String, message: String) {
        mutate { state, _ in state.failures["\(domain).\(service)"] = (code, message) }
    }

    public func clearFailures() {
        mutate { state, _ in state.failures = [:] }
    }

    var snapshot: Snapshot {
        state.withLock { $0.snapshot }
    }

    /// Returns once `condition` holds, checked after every change to the server or its connections.
    func waitUntil(_ condition: @escaping @Sendable (Snapshot) -> Bool) async {
        await withCheckedContinuation { continuation in
            mutate { state, _ in state.watchers.append(Watcher(condition: condition, continuation: continuation)) }
        }
    }

    fileprivate func send(_ text: String, on id: Int?) throws {
        let delivered = mutate { state, _ -> Bool in
            guard let id, state.connections[id]?.closesAfterDrain == false else { return false }
            handle(text, on: id, in: &state)
            return true
        }
        if !delivered { throw URLError(id == nil ? .cannotConnectToHost : .networkConnectionLost) }
    }

    fileprivate func receive(on id: Int?) async throws -> String {
        guard let id else { throw URLError(.cannotConnectToHost) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                mutate { state, effects in
                    guard state.connections[id] != nil, state.connections[id]?.waiter == nil else {
                        effects.append(.fail(continuation, .networkConnectionLost))
                        return
                    }
                    state.connections[id]?.waiter = continuation
                }
            }
        } onCancel: {
            close(id)
        }
    }

    fileprivate func close(_ id: Int?) {
        guard let id else { return }
        mutate { state, effects in
            if let waiter = state.connections.removeValue(forKey: id)?.waiter {
                effects.append(.fail(waiter, .cancelled))
            }
        }
    }

    private func mutate<T: Sendable>(_ body: (inout State, inout [Effect]) -> T) -> T {
        let (value, effects) = state.withLock { state -> (T, [Effect]) in
            var effects: [Effect] = []
            let value = body(&state, &effects)
            Self.pump(&state, into: &effects)
            let snapshot = state.snapshot
            state.watchers.removeAll { watcher in
                guard watcher.condition(snapshot) else { return false }
                effects.append(.wake(watcher.continuation))
                return true
            }
            return (value, effects)
        }
        for effect in effects {
            switch effect {
            case .deliver(let continuation, let frame): continuation.resume(returning: frame)
            case .fail(let continuation, let code): continuation.resume(throwing: URLError(code))
            case .wake(let continuation): continuation.resume()
            }
        }
        return value
    }

    private static func pump(_ state: inout State, into effects: inout [Effect]) {
        for (id, connection) in state.connections {
            guard let waiter = connection.waiter else { continue }
            if let frame = connection.outbound.first {
                state.connections[id]?.outbound.removeFirst()
                state.connections[id]?.waiter = nil
                effects.append(.deliver(waiter, frame))
            } else if connection.closesAfterDrain {
                state.connections[id] = nil
                effects.append(.fail(waiter, .networkConnectionLost))
            }
        }
    }

    private func handle(_ text: String, on id: Int, in state: inout State) {
        guard let message = try? JSONDecoder().decode(HAValue.self, from: Data(text.utf8)),
              let type = message["type"]?.string,
              let connection = state.connections[id] else {
            state.received.append(text)
            return
        }
        guard connection.authenticated else {
            state.received.append(type == "auth" ? HAOutbound.auth(token: "redacted") : text)
            let token = message["access_token"]?.string ?? ""
            let accepted = type == "auth" && (state.expectedToken.map { $0 == token } ?? !token.isEmpty)
            if accepted {
                state.connections[id]?.authenticated = true
                state.connections[id]?.outbound.append(Self.encode(["type": .string("auth_ok"), "ha_version": .string(state.version)]))
            } else {
                state.connections[id]?.outbound.append(Self.encode(["type": .string("auth_invalid"), "message": .string("Invalid access token or password")]))
                state.connections[id]?.closesAfterDrain = true
            }
            return
        }
        state.received.append(text)
        guard let messageID = message["id"]?.number.flatMap({ Int(exactly: $0) }) else {
            state.connections[id]?.outbound.append(Self.error(id: 0, code: "invalid_format", message: "Message incorrectly formatted."))
            return
        }
        guard messageID > connection.lastID else {
            state.connections[id]?.outbound.append(Self.error(id: messageID, code: "id_reuse", message: "Identifier values have to increase."))
            return
        }
        state.connections[id]?.lastID = messageID
        switch type {
        case "subscribe_events":
            if message["event_type"]?.string ?? "state_changed" == "state_changed" {
                state.connections[id]?.subscriptions.append(messageID)
            }
            state.connections[id]?.outbound.append(Self.success(id: messageID, result: .null))
        case "get_states":
            let states = state.entities.values.sorted { $0.entityID < $1.entityID }.map(\.wireValue)
            state.connections[id]?.outbound.append(Self.success(id: messageID, result: .array(states)))
        case "call_service":
            callService(message, id: messageID, on: id, in: &state)
        case "ping":
            if state.respondsToPings {
                state.connections[id]?.outbound.append(Self.encode(["id": .number(Double(messageID)), "type": .string("pong")]))
            }
        default:
            state.connections[id]?.outbound.append(Self.error(id: messageID, code: "unknown_command", message: "Unknown command."))
        }
    }

    private func callService(_ message: HAValue, id messageID: Int, on id: Int, in state: inout State) {
        let domain = message["domain"]?.string ?? ""
        let service = message["service"]?.string ?? ""
        let targets = Self.entityIDs(message["target"]?["entity_id"]) + Self.entityIDs(message["service_data"]?["entity_id"])
        state.serviceCalls.append(ServiceCall(domain: domain, service: service, entityIDs: targets))
        guard !state.ignoresServiceCalls else { return }
        if let failure = state.failures["\(domain).\(service)"] {
            state.connections[id]?.outbound.append(Self.error(id: messageID, code: failure.code, message: failure.message))
            return
        }
        let stamp = now()
        let change: (HAEntity) -> HAEntity
        if Self.switchable.contains(domain), ["turn_on", "turn_off", "toggle"].contains(service) {
            change = { entity in
                var entity = entity
                let on = service == "toggle" ? entity.state != "on" : service == "turn_on"
                entity.state = on ? "on" : "off"
                return entity
            }
        } else if ["script", "scene"].contains(domain), service == "turn_on" {
            change = { entity in
                var entity = entity
                entity.attributes["last_triggered"] = .string(HADate.format(stamp))
                if domain == "scene" { entity.state = HADate.format(stamp) }
                return entity
            }
        } else if domain == "input_button", service == "press" {
            change = { entity in
                var entity = entity
                entity.state = HADate.format(stamp)
                return entity
            }
        } else {
            state.connections[id]?.outbound.append(Self.error(id: messageID, code: "not_found", message: "Service \(domain).\(service) not found."))
            return
        }
        for entityID in targets {
            guard let old = state.entities[entityID] else { continue }
            var new = change(old)
            guard new != old else { continue }
            if new.state != old.state { new.lastChanged = stamp }
            new.lastUpdated = stamp
            state.entities[entityID] = new
            Self.broadcast(entityID: entityID, old: old, new: new, at: stamp, in: &state)
        }
        state.contexts += 1
        let context = HAValue.object(["id": .string(Self.contextID(state.contexts)), "parent_id": .null, "user_id": .null])
        state.connections[id]?.outbound.append(Self.success(id: messageID, result: .object(["context": context, "response": .null])))
    }

    private static func broadcast(entityID: String, old: HAEntity?, new: HAEntity?, at stamp: Date, in state: inout State) {
        state.contexts += 1
        let event = HAValue.object([
            "event_type": .string("state_changed"),
            "data": .object([
                "entity_id": .string(entityID),
                "old_state": old?.wireValue ?? .null,
                "new_state": new?.wireValue ?? .null,
            ]),
            "origin": .string("LOCAL"),
            "time_fired": .string(HADate.format(stamp)),
            "context": .object(["id": .string(contextID(state.contexts)), "parent_id": .null, "user_id": .null]),
        ])
        for (id, connection) in state.connections where connection.authenticated {
            for subscription in connection.subscriptions {
                state.connections[id]?.outbound.append(encode(["id": .number(Double(subscription)), "type": .string("event"), "event": event]))
            }
        }
    }

    private static func entityIDs(_ value: HAValue?) -> [String] {
        switch value {
        case .string(let id): [id]
        case .array(let ids): ids.compactMap(\.string)
        default: []
        }
    }

    private static func contextID(_ number: Int) -> String {
        "01FIXTURE" + String(format: "%017d", number)
    }

    private static func success(id: Int, result: HAValue) -> String {
        encode(["id": .number(Double(id)), "type": .string("result"), "success": .bool(true), "result": result])
    }

    private static func error(id: Int, code: String, message: String) -> String {
        encode([
            "id": .number(Double(id)),
            "type": .string("result"),
            "success": .bool(false),
            "error": .object(["code": .string(code), "message": .string(message)]),
        ])
    }

    private static func encode(_ object: [String: HAValue]) -> String {
        HAOutbound.encode(object)
    }
}

private struct FixtureHATransport: HATransport {
    let server: FixtureHATransportFactory
    /// nil when the server refused the connection.
    let connection: Int?

    func send(_ text: String) async throws {
        try server.send(text, on: connection)
    }

    func receive() async throws -> String {
        try await server.receive(on: connection)
    }

    func close() {
        server.close(connection)
    }
}
