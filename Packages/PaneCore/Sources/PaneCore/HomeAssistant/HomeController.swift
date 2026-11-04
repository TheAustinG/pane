import Foundation
import Observation

/// Owns the Home Assistant connection: the server address and token, the live entity states, the
/// owner's entity selection and nudge preferences, and the nudges they raise. The app reads it.
@MainActor
@Observable
public final class HomeController {
    public private(set) var connection: HomeConnection = .notConfigured {
        didSet {
            guard connection != oldValue else { return }
            connectionHistory.append(connection)
            if connectionHistory.count > 100 { connectionHistory.removeFirst() }
        }
    }
    public private(set) var server: HomeServer?
    /// Live states keyed by entity id, with `debugOverrides` laid over them.
    public private(set) var entities: [String: HAEntity] = [:]
    public private(set) var nudges: [HomeNudge] = []
    /// When the last `state_changed` event arrived.
    public private(set) var lastEventAt: Date?
    /// Successful connections after the first, for the soak log.
    public private(set) var reconnectCount = 0

    public var selection: HomeSelection = .empty {
        didSet {
            guard selection != oldValue else { return }
            save(selection, forKey: Keys.selection)
            recomputeNudges()
        }
    }
    public var nudgePreferences = HomeNudgePreferences() {
        didSet {
            guard nudgePreferences != oldValue else { return }
            save(nudgePreferences, forKey: Keys.nudges)
            recomputeNudges()
        }
    }
    /// Debug: states laid over the live ones, so each nudge can be raised and cleared on demand.
    public var debugOverrides: [String: HAEntity] = [:] {
        didSet {
            guard debugOverrides != oldValue else { return }
            rebuildEntities()
        }
    }
    /// App time for the time-of-day nudges; the app points it at its debug clock.
    @ObservationIgnored public var now: @MainActor () -> Date = { .now } {
        didSet { recomputeNudges() }
    }
    /// The in-process server behind a `preview` controller, for fixture runs to change states.
    @ObservationIgnored public private(set) var fixture: FixtureHATransportFactory?

    static let requestTimeout: TimeInterval = 10
    /// `get_states` can run to megabytes on a large install.
    static let snapshotTimeout: TimeInterval = 30
    static let pingInterval: TimeInterval = 30
    static let pongTimeout: TimeInterval = 10
    static let nudgeInterval: TimeInterval = 60
    /// How often an idle loop (no server, or a rejected token) wakes to look again.
    static let idleInterval: TimeInterval = 3600

    enum Keys {
        static let server = "home.server"
        static let selection = "home.selection"
        static let nudges = "home.nudges"
        static let all = [server, selection, nudges]
    }

    @ObservationIgnored var calendar: Calendar = .current
    /// Every distinct `connection` value in order, newest last, for tests.
    @ObservationIgnored private(set) var connectionHistory: [HomeConnection] = []

    @ObservationIgnored private let store: any KeyValueStore
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let transport: any HATransportFactory
    @ObservationIgnored private let clock: any WeatherClock
    @ObservationIgnored private let backoff: ReconnectBackoff
    @ObservationIgnored private var live: [String: HAEntity] = [:]
    @ObservationIgnored private var session: HASession?
    @ObservationIgnored private var hasSnapshot = false
    @ObservationIgnored private var earlyChanges: [HAStateChange] = []
    @ObservationIgnored private var authRejected = false
    @ObservationIgnored private var reconnectNow = false
    @ObservationIgnored private var hasConnected = false
    @ObservationIgnored private var failedAttempts = 0
    @ObservationIgnored private var downSince: Date?
    @ObservationIgnored private var sleeper: Task<Void, any Error>?

    public init(
        store: any KeyValueStore = UserDefaultsKeyValueStore(),
        secrets: any SecretStore,
        transport: any HATransportFactory,
        clock: any WeatherClock = SystemWeatherClock(),
        backoff: ReconnectBackoff = ReconnectBackoff()
    ) {
        self.store = store
        self.secrets = secrets
        self.transport = transport
        self.clock = clock
        self.backoff = backoff
        server = store.data(forKey: Keys.server)
            .map { String(decoding: $0, as: UTF8.self) }
            .flatMap(HomeServer.init(address:))
        selection = Self.load(HomeSelection.self, from: store, key: Keys.selection) ?? .empty
        nudgePreferences = Self.load(HomeNudgePreferences.self, from: store, key: Keys.nudges) ?? HomeNudgePreferences()
        connection = isConfigured ? .connecting : .notConfigured
    }

    public var summary: HomeSummary {
        HomeSummary.make(entities: entities, selection: selection, nudges: nudges)
    }

    public var hasToken: Bool {
        storedToken != nil
    }

    /// Saves the address and token and reconnects with them.
    public func configure(server: HomeServer, token: String) throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try secrets.setString(token.isEmpty ? nil : token, for: .homeAssistantToken)
        if server != self.server { clearEntities() }
        self.server = server
        store.set(Data(server.address.utf8), forKey: Keys.server)
        authRejected = false
        connection = isConfigured ? .connecting : .notConfigured
        restartConnection()
    }

    public func forget() throws {
        try secrets.setString(nil, for: .homeAssistantToken)
        server = nil
        selection = .empty
        nudgePreferences = HomeNudgePreferences()
        debugOverrides = [:]
        clearEntities()
        authRejected = false
        Self.clearStore(store)
        connection = .notConfigured
        restartConnection()
    }

    /// Clears everything `HomeController` saves, for the app's `-resetSettings`.
    public static func reset(store: any KeyValueStore = UserDefaultsKeyValueStore(), secrets: any SecretStore) {
        clearStore(store)
        try? secrets.setString(nil, for: .homeAssistantToken)
    }

    /// Connects, keeps entity states current, and reconnects with backoff after a drop. Runs until
    /// the calling task is cancelled.
    public func run() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.tickNudges() }
            await self.connectLoop()
            group.cancelAll()
        }
    }

    /// Runs a scene button: `scene.turn_on`, `script.turn_on` or `input_button.press`.
    public func activateScene(_ entityID: String) async throws {
        let domain = HAEntity.domain(of: entityID)
        switch domain {
        case "scene", "script":
            try await callService(domain: domain, service: "turn_on", entityID: entityID)
        case "input_button":
            try await callService(domain: domain, service: "press", entityID: entityID)
        default:
            throw HomeServiceError.unsupportedDomain(domain)
        }
    }

    public func callService(domain: String, service: String, entityID: String) async throws {
        guard connection.isConnected, let session, !session.isClosed else { throw HomeServiceError.notConnected }
        do {
            _ = try await session.request(
                { HAOutbound.callService(id: $0, domain: domain, service: service, entityID: entityID) },
                until: clock.now.addingTimeInterval(Self.requestTimeout)
            )
        } catch HASession.Failure.rejected(let error) {
            throw HomeServiceError.failed(code: error.code, message: error.message)
        } catch HASession.Failure.timeout {
            throw HomeServiceError.timeout
        } catch {
            throw HomeServiceError.connectionLost
        }
    }

    /// Debug: drops the socket as if the network failed; `run()` reconnects on its own.
    public func forceDisconnect() {
        session?.close()
    }

    /// The setup screen's test: authenticates and counts entities, then closes.
    public static func testConnection(
        server: HomeServer,
        token: String,
        transport: any HATransportFactory,
        timeout: TimeInterval = 10
    ) async -> Result<HomeServerInfo, HomeSetupError> {
        await testConnection(server: server, token: token, transport: transport, timeout: timeout, clock: SystemWeatherClock())
    }

    static func testConnection(
        server: HomeServer,
        token: String,
        transport factory: any HATransportFactory,
        timeout: TimeInterval,
        clock: any WeatherClock
    ) async -> Result<HomeServerInfo, HomeSetupError> {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return .failure(.invalidToken) }
        let transport = factory.connect(to: server.webSocketURL)
        let session = HASession(transport: transport, clock: clock)
        defer { session.close() }
        let deadline = clock.now.addingTimeInterval(timeout)
        return await withTaskCancellationHandler {
            do {
                let version = try await session.authenticate(token: token, until: deadline)
                session.start()
                guard case .states(let states)? = try await session.request(HAOutbound.getStates, until: deadline) else {
                    return .failure(.unexpectedReply("get_states did not return a list of states"))
                }
                return .success(HomeServerInfo(version: version, entityCount: states.count))
            } catch let failure as HASession.Failure {
                switch failure {
                case .closed: return .failure(.unreachable)
                case .timeout: return .failure(.timeout)
                case .authInvalid: return .failure(.invalidToken)
                case .unexpectedReply(let reason): return .failure(.unexpectedReply(reason))
                case .rejected(let error): return .failure(.unexpectedReply("\(error.code): \(error.message)"))
                }
            } catch {
                return .failure(.unreachable)
            }
        } onCancel: {
            transport.close()
        }
    }

    /// A controller on the real code path against an in-process server holding `entities`. The
    /// caller still runs it; `fixture` is the server.
    public static func preview(entities: [HAEntity], selection: HomeSelection) -> HomeController {
        let fixture = FixtureHATransportFactory(entities: entities)
        let controller = HomeController(store: InMemoryKeyValueStore(), secrets: InMemorySecretStore(), transport: fixture)
        controller.fixture = fixture
        try? controller.configure(server: fixtureServer, token: FixtureHATransportFactory.defaultToken)
        controller.selection = selection
        controller.live = Dictionary(entities.map { ($0.entityID, $0) }, uniquingKeysWith: { _, last in last })
        controller.rebuildEntities()
        return controller
    }

    static let fixtureServer = HomeServer(address: "http://fixture.invalid")!

    private var storedToken: String? {
        guard let token = (try? secrets.string(for: .homeAssistantToken)) ?? nil, !token.isEmpty else { return nil }
        return token
    }

    private var isConfigured: Bool {
        server != nil && storedToken != nil
    }

    private func connectLoop() async {
        while !Task.isCancelled {
            reconnectNow = false
            guard let server, let token = storedToken else {
                connection = .notConfigured
                await sleep(until: clock.now.addingTimeInterval(Self.idleInterval))
                continue
            }
            if authRejected {
                connection = .authFailed
                await sleep(until: clock.now.addingTimeInterval(Self.idleInterval))
                continue
            }
            connection = .connecting
            let outcome = await runSession(server: server, token: token)
            if Task.isCancelled { break }
            if reconnectNow { continue }
            switch outcome {
            case .authRejected:
                authRejected = true
            case .ended:
                let now = clock.now
                let since = downSince ?? now
                downSince = since
                let retryAt = now.addingTimeInterval(backoff.delay(attempt: failedAttempts))
                failedAttempts += 1
                connection = .disconnected(since: since, retryAt: retryAt)
                await sleep(until: retryAt)
            }
        }
        if isConfigured, connection != .authFailed {
            connection = .disconnected(since: downSince ?? clock.now, retryAt: nil)
        }
    }

    private enum SessionOutcome {
        case authRejected
        case ended
    }

    private func runSession(server: HomeServer, token: String) async -> SessionOutcome {
        let transport = transport.connect(to: server.webSocketURL)
        let session = HASession(transport: transport, clock: clock)
        self.session = session
        hasSnapshot = false
        earlyChanges = []
        defer {
            session.close()
            if self.session === session { self.session = nil }
        }
        return await withTaskCancellationHandler {
            await converse(over: session, token: token)
        } onCancel: {
            transport.close()
        }
    }

    private func converse(over session: HASession, token: String) async -> SessionOutcome {
        let version: String
        do {
            version = try await session.authenticate(token: token, until: clock.now.addingTimeInterval(Self.requestTimeout))
        } catch HASession.Failure.authInvalid {
            return .authRejected
        } catch {
            return .ended
        }
        session.onEvent = { [weak self, weak session] change in
            guard let self, let session, self.session === session else { return }
            self.receive(change)
        }
        session.start()
        do {
            // Subscribing first means a change made while the snapshot is in flight is not lost.
            _ = try await session.request(HAOutbound.subscribeStateChanged, until: clock.now.addingTimeInterval(Self.requestTimeout))
            let reply = try await session.request(HAOutbound.getStates, until: clock.now.addingTimeInterval(Self.snapshotTimeout))
            guard case .states(let states)? = reply else { return .ended }
            applySnapshot(states)
        } catch {
            return .ended
        }
        if hasConnected { reconnectCount += 1 }
        hasConnected = true
        failedAttempts = 0
        downSince = nil
        connection = .connected(version: version)
        let heartbeat = Task { await self.heartbeat(session) }
        await session.waitUntilClosed()
        heartbeat.cancel()
        return .ended
    }

    /// Pings every `pingInterval`; a socket that sends nothing at all within `pongTimeout` of a ping
    /// is dead, though the system may not notice for minutes.
    private func heartbeat(_ session: HASession) async {
        let clock = clock
        var nextPing = clock.now.addingTimeInterval(Self.pingInterval)
        while !session.isClosed {
            do {
                try await clock.sleep(until: nextPing)
            } catch {
                return
            }
            guard !session.isClosed else { return }
            let sentAt = clock.now
            let seen = session.framesReceived
            session.send(HAOutbound.ping)
            do {
                try await clock.sleep(until: sentAt.addingTimeInterval(Self.pongTimeout))
            } catch {
                return
            }
            if session.framesReceived == seen {
                session.close()
                return
            }
            nextPing = sentAt.addingTimeInterval(Self.pingInterval)
        }
    }

    private func tickNudges() async {
        let clock = clock
        while !Task.isCancelled {
            do {
                try await clock.sleep(until: clock.now.addingTimeInterval(Self.nudgeInterval))
            } catch {
                return
            }
            recomputeNudges()
        }
    }

    private func receive(_ change: HAStateChange) {
        lastEventAt = clock.now
        guard hasSnapshot else {
            earlyChanges.append(change)
            return
        }
        live[change.entityID] = change.newState
        refresh(change.entityID)
    }

    private func applySnapshot(_ states: [HAEntity]) {
        let fresh = Self.merge(snapshot: states, earlyChanges: earlyChanges)
        earlyChanges = []
        hasSnapshot = true
        live = fresh
        rebuildEntities()
    }

    /// Changes that arrived before the snapshot are applied only where they are newer than it.
    nonisolated static func merge(snapshot states: [HAEntity], earlyChanges: [HAStateChange]) -> [String: HAEntity] {
        var fresh = Dictionary(states.map { ($0.entityID, $0) }, uniquingKeysWith: { _, last in last })
        for change in earlyChanges {
            guard let current = fresh[change.entityID] else {
                // Created after the snapshot was taken; removals of unknown entities need nothing.
                if let created = change.newState { fresh[change.entityID] = created }
                continue
            }
            let changedAt = change.newState?.lastUpdated ?? change.timeFired
            guard let since = current.lastUpdated, let changedAt else {
                fresh[change.entityID] = change.newState
                continue
            }
            if changedAt > since { fresh[change.entityID] = change.newState }
        }
        return fresh
    }

    private func refresh(_ entityID: String) {
        let value = debugOverrides[entityID] ?? live[entityID]
        if entities[entityID] != value { entities[entityID] = value }
        recomputeNudges()
    }

    private func rebuildEntities() {
        let merged = live.merging(debugOverrides) { _, override in override }
        if merged != entities { entities = merged }
        recomputeNudges()
    }

    private func clearEntities() {
        live = [:]
        hasSnapshot = false
        earlyChanges = []
        lastEventAt = nil
        rebuildEntities()
    }

    private func recomputeNudges() {
        let fresh = HomeNudgeRules.evaluate(
            entities: entities,
            selection: selection,
            preferences: nudgePreferences,
            previous: nudges,
            at: now(),
            calendar: calendar
        )
        if fresh != nudges { nudges = fresh }
    }

    private func restartConnection() {
        reconnectNow = true
        failedAttempts = 0
        downSince = nil
        session?.close()
        wakeLoop()
    }

    private func sleep(until deadline: Date) async {
        let clock = clock
        let task = Task { try await clock.sleep(until: deadline) }
        sleeper = task
        await withTaskCancellationHandler {
            _ = try? await task.value
        } onCancel: {
            task.cancel()
        }
        sleeper = nil
    }

    private func wakeLoop() {
        sleeper?.cancel()
    }

    private func save(_ value: some Encodable, forKey key: String) {
        store.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, from store: any KeyValueStore, key: String) -> T? {
        store.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func clearStore(_ store: any KeyValueStore) {
        Keys.all.forEach { store.set(nil, forKey: $0) }
    }
}

/// Why a service call or scene button failed. Never carries the token.
public enum HomeServiceError: Error, Hashable, Sendable, LocalizedError {
    case notConnected
    case timeout
    /// The socket dropped before Home Assistant answered.
    case connectionLost
    /// Home Assistant refused the call, with its error code and message.
    case failed(code: String, message: String)
    /// `activateScene` only runs scenes, scripts and input buttons.
    case unsupportedDomain(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to Home Assistant"
        case .timeout: "Home Assistant did not answer in time"
        case .connectionLost: "The connection to Home Assistant dropped"
        case .failed(let code, let message): message.isEmpty ? "Home Assistant refused the call (\(code))" : message
        case .unsupportedDomain(let domain): "Cannot run a \(domain) entity as a scene"
        }
    }
}
