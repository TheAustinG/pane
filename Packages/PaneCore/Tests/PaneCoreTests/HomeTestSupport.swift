import Foundation
import Observation
import Synchronization
@testable import PaneCore

/// Invented entities for a small home. No real names or ids.
enum HomeSample {
    static let start = WeatherFixture.local(2026, 11, 2, 14)
    static let calendar = WeatherFixture.calendar
    static let token = "sample-token"
    static let server = HomeServer(address: "http://ha.fixture.invalid:8123")!
    static let otherServer = HomeServer(address: "https://other.fixture.invalid")!

    static func entity(_ id: String, _ state: String, _ attributes: [String: HAValue] = [:], name: String? = nil) -> HAEntity {
        var attributes = attributes
        if let name { attributes["friendly_name"] = .string(name) }
        return HAEntity(entityID: id, state: state, attributes: attributes, lastChanged: start, lastUpdated: start)
    }

    static func humidity(_ id: String, _ state: String) -> HAEntity {
        entity(id, state, ["device_class": .string("humidity"), "unit_of_measurement": .string("%")])
    }

    static let entities: [HAEntity] = [
        entity("climate.den", "heat", ["current_temperature": .number(70), "temperature": .number(68), "hvac_action": .string("idle")], name: "Den"),
        humidity("sensor.loft_humidity", "45"),
        humidity("sensor.studio_humidity", "50"),
        entity("lock.side_gate", "locked", name: "Side Gate"),
        entity("light.pantry", "off", name: "Pantry"),
        entity("light.gazebo", "off", name: "Gazebo"),
        entity("switch.reading_nook", "off", name: "Reading Nook"),
        entity("person.robin", "home", name: "Robin"),
        entity("person.kit", "home", name: "Kit"),
        entity("media_player.loft_tv", "off", name: "Loft TV"),
        entity("scene.good_night", "2026-11-01T04:00:00.000000+00:00", name: "Good Night"),
        entity("script.film_night", "off", ["last_triggered": .null], name: "Film Night"),
        entity("input_button.test_chime", "unknown", name: "Test Chime"),
        entity("input_boolean.fixture_toggle", "off", name: "Fixture Toggle"),
    ]

    static let selection = HomeSelection(
        thermostat: "climate.den",
        humiditySensors: ["sensor.loft_humidity", "sensor.studio_humidity"],
        lock: "lock.side_gate",
        lights: ["light.pantry", "light.gazebo"],
        people: ["person.robin", "person.kit"],
        bedroomTV: "media_player.loft_tv",
        scenes: ["scene.good_night", "script.film_night", "input_button.test_chime"]
    )

    static var byID: [String: HAEntity] {
        Dictionary(uniqueKeysWithValues: entities.map { ($0.entityID, $0) })
    }
}

/// A clock that only moves when the test says so, and can report what is asleep on it.
final class SteppingClock: WeatherClock {
    private struct Sleeper {
        let id: Int
        let deadline: Date
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct Watcher {
        let deadline: Date
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var now: Date
        var nextID = 0
        var sleepers: [Sleeper] = []
        var cancelled: Set<Int> = []
        var watchers: [Watcher] = []
    }

    private let state: Mutex<State>

    init(now: Date) {
        state = Mutex(State(now: now))
    }

    var now: Date { state.withLock { $0.now } }

    var deadlines: [Date] { state.withLock { $0.sleepers.map(\.deadline).sorted() } }

    func sleep(until deadline: Date) async throws {
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enum Outcome { case cancelled, elapsed, waiting([CheckedContinuation<Void, Never>]) }
                let outcome = state.withLock { state -> Outcome in
                    if state.cancelled.remove(id) != nil { return .cancelled }
                    if deadline <= state.now { return .elapsed }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    let asleep = state.sleepers.filter { $0.deadline == deadline }.count
                    let isReady: (Watcher) -> Bool = { $0.deadline == deadline && $0.count <= asleep }
                    let ready = state.watchers.filter(isReady).map(\.continuation)
                    state.watchers.removeAll(where: isReady)
                    return .waiting(ready)
                }
                switch outcome {
                case .cancelled: continuation.resume(throwing: CancellationError())
                case .elapsed: continuation.resume()
                case .waiting(let ready): ready.forEach { $0.resume() }
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                if let index = state.sleepers.firstIndex(where: { $0.id == id }) {
                    return state.sleepers.remove(at: index)
                }
                state.cancelled.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by interval: TimeInterval) {
        let woken = state.withLock { state -> [Sleeper] in
            state.now = state.now.addingTimeInterval(interval)
            let now = state.now
            let woken = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return woken
        }
        woken.forEach { $0.continuation.resume() }
    }

    /// Returns once `count` sleepers are asleep until exactly `deadline`.
    func waitForSleeper(until deadline: Date, count: Int = 1) async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Bool in
                if state.sleepers.filter({ $0.deadline == deadline }).count >= count { return true }
                state.watchers.append(Watcher(deadline: deadline, count: count, continuation: continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}

/// Returns once `condition` holds. It must read only observable state, which is re-checked on
/// every change to it.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    while !condition() {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = condition()
            } onChange: {
                continuation.resume()
            }
        }
    }
}

/// Passes connections through to another factory and records where each one went.
final class RecordingFactory: HATransportFactory {
    let base: any HATransportFactory
    private let urls = Mutex<[URL]>([])

    init(_ base: any HATransportFactory) {
        self.base = base
    }

    var connectedURLs: [URL] { urls.withLock { $0 } }

    func connect(to url: URL) -> any HATransport {
        urls.withLock { $0.append(url) }
        return base.connect(to: url)
    }
}

/// A server that sends `frames` in order, records what the client sends, then goes quiet until
/// closed. With no frames it is a socket that connected but never speaks.
final class ScriptedTransportFactory: HATransportFactory {
    private let frames: [String]
    let transports = Mutex<[ScriptedTransport]>([])

    init(frames: [String] = []) {
        self.frames = frames
    }

    func connect(to url: URL) -> any HATransport {
        let transport = ScriptedTransport(frames: frames)
        transports.withLock { $0.append(transport) }
        return transport
    }
}

final class ScriptedTransport: HATransport {
    private struct State {
        var frames: [String]
        var sent: [String] = []
        var closed = false
        var waiter: CheckedContinuation<String, any Error>?
    }

    private let state: Mutex<State>

    init(frames: [String]) {
        state = Mutex(State(frames: frames))
    }

    var sent: [String] { state.withLock { $0.sent } }
    var isClosed: Bool { state.withLock { $0.closed } }

    func send(_ text: String) async throws {
        try state.withLock { state in
            guard !state.closed else { throw URLError(.networkConnectionLost) }
            state.sent.append(text)
        }
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            enum Outcome { case frame(String), closed, waiting }
            let outcome = state.withLock { state -> Outcome in
                if state.closed { return .closed }
                if !state.frames.isEmpty { return .frame(state.frames.removeFirst()) }
                state.waiter = continuation
                return .waiting
            }
            switch outcome {
            case .frame(let text): continuation.resume(returning: text)
            case .closed: continuation.resume(throwing: URLError(.networkConnectionLost))
            case .waiting: break
            }
        }
    }

    func close() {
        let waiter = state.withLock { state -> CheckedContinuation<String, any Error>? in
            state.closed = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(throwing: URLError(.cancelled))
    }
}

/// A controller wired to the fixture server, a stepping clock and in-memory stores.
@MainActor
final class HomeHarness {
    let clock: SteppingClock
    let fixture: FixtureHATransportFactory
    let factory: RecordingFactory
    let store: InMemoryKeyValueStore
    let secrets: InMemorySecretStore
    let controller: HomeController
    private var task: Task<Void, Never>?

    init(
        entities: [HAEntity] = HomeSample.entities,
        configured: Bool = true,
        token: String = HomeSample.token,
        expectedToken: String? = HomeSample.token,
        backoff: ReconnectBackoff = ReconnectBackoff(jitter: 0),
        store: InMemoryKeyValueStore = InMemoryKeyValueStore(),
        secrets: InMemorySecretStore = InMemorySecretStore()
    ) {
        let clock = SteppingClock(now: HomeSample.start)
        self.clock = clock
        fixture = FixtureHATransportFactory(entities: entities, expectedToken: expectedToken, now: { clock.now })
        factory = RecordingFactory(fixture)
        self.store = store
        self.secrets = secrets
        controller = HomeController(store: store, secrets: secrets, transport: factory, clock: clock, backoff: backoff)
        controller.calendar = HomeSample.calendar
        controller.now = { clock.now }
        if configured {
            try! controller.configure(server: HomeSample.server, token: token)
        }
    }

    func launch() {
        let controller = controller
        task = Task { await controller.run() }
    }

    /// Launches and waits for the first good connection and its heartbeat.
    func connect() async {
        launch()
        await waitUntil { self.controller.connection.isConnected }
        await clock.waitForSleeper(until: clock.now.addingTimeInterval(HomeController.pingInterval))
    }

    func stop() async {
        task?.cancel()
        await task?.value
        task = nil
    }

    /// Client frames the fixture received, parsed.
    var received: [HAValue] {
        fixture.snapshot.received.compactMap { try? JSONDecoder().decode(HAValue.self, from: Data($0.utf8)) }
    }

    func receivedTypes() -> [String] {
        received.compactMap { $0["type"]?.string }
    }
}

extension HAValue {
    var int: Int? { number.flatMap { Int(exactly: $0) } }
}
