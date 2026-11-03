import Foundation
import Observation

/// Owns the Home Assistant connection: the server address and token, the live entity states, the
/// owner's entity selection and nudge preferences, and the nudges they raise. The app reads it.
@MainActor
@Observable
public final class HomeController {
    public private(set) var connection: HomeConnection = .notConfigured
    public private(set) var server: HomeServer?
    /// Live states keyed by entity id, with `debugOverrides` laid over them.
    public private(set) var entities: [String: HAEntity] = [:]
    public private(set) var nudges: [HomeNudge] = []
    /// When the last `state_changed` event arrived.
    public private(set) var lastEventAt: Date?
    /// Successful connections after the first, for the soak log.
    public private(set) var reconnectCount = 0

    public var selection: HomeSelection = .empty
    public var nudgePreferences = HomeNudgePreferences()
    /// Debug: states laid over the live ones, so each nudge can be raised and cleared on demand.
    public var debugOverrides: [String: HAEntity] = [:]
    /// App time for the time-of-day nudges; the app points it at its debug clock.
    @ObservationIgnored public var now: @MainActor () -> Date = { .now }

    @ObservationIgnored private let store: any KeyValueStore
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let transport: any HATransportFactory
    @ObservationIgnored private let clock: any WeatherClock
    @ObservationIgnored private let backoff: ReconnectBackoff

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
    }

    public var summary: HomeSummary {
        HomeSummary.make(entities: entities, selection: selection, nudges: nudges)
    }

    public var hasToken: Bool {
        ((try? secrets.string(for: .homeAssistantToken)) ?? nil)?.isEmpty == false
    }

    /// Saves the address and token and reconnects with them.
    public func configure(server: HomeServer, token: String) throws {
        self.server = server
    }

    /// Clears the address, token, selection and preferences.
    public func forget() throws {
        server = nil
        connection = .notConfigured
    }

    /// Connects, keeps entity states current, and reconnects with backoff after a drop. Runs until
    /// the calling task is cancelled.
    public func run() async {}

    /// Runs a scene button: `scene.turn_on`, `script.turn_on` or `input_button.press`.
    public func activateScene(_ entityID: String) async throws {}

    public func callService(domain: String, service: String, entityID: String) async throws {}

    /// Debug: drops the socket as if the network failed; `run()` reconnects on its own.
    public func forceDisconnect() {}

    /// The setup screen's test: authenticates and counts entities, then closes.
    public static func testConnection(
        server: HomeServer,
        token: String,
        transport: any HATransportFactory,
        timeout: TimeInterval = 10
    ) async -> Result<HomeServerInfo, HomeSetupError> {
        .failure(.unreachable)
    }

    /// Placeholder until the fixture transport lands: shows `entities` as if connected.
    public static func preview(entities: [HAEntity], selection: HomeSelection) -> HomeController {
        let controller = HomeController(store: InMemoryKeyValueStore(), secrets: InMemorySecretStore(), transport: NoTransportFactory())
        controller.entities = Dictionary(uniqueKeysWithValues: entities.map { ($0.entityID, $0) })
        controller.selection = selection
        controller.connection = .connected(version: "preview")
        return controller
    }
}

private struct NoTransportFactory: HATransportFactory {
    func connect(to url: URL) -> any HATransport { NoTransport() }
}

private struct NoTransport: HATransport {
    func send(_ text: String) async throws { throw URLError(.notConnectedToInternet) }
    func receive() async throws -> String { throw URLError(.notConnectedToInternet) }
    func close() {}
}
