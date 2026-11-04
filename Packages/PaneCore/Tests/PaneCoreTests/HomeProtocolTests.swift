import Foundation
import Synchronization
import Testing
@testable import PaneCore

/// A session recorded from a real Home Assistant 2026.10.4 and scrubbed: every entity id, name,
/// context id, user id, location and free-text attribute is invented, timestamps are shifted, and
/// the token is replaced. It holds auth, `subscribe_events`, `get_states` trimmed to 15 entities,
/// two toggles of a test helper with their events, and a ping.
enum Transcript {
    struct Entry: Decodable, Sendable {
        let dir: String
        let frame: HAValue
    }

    static let entries: [Entry] = {
        let url = Bundle.module.url(forResource: "ha-transcript", withExtension: "jsonl", subdirectory: "Fixtures")!
        let text = try! String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").map { try! JSONDecoder().decode(Entry.self, from: Data($0.utf8)) }
    }()

    static var serverFrames: [HAValue] { entries.filter { $0.dir == "in" }.map(\.frame) }
    static var clientFrames: [HAValue] { entries.filter { $0.dir == "out" }.map(\.frame) }

    static let toggle = "input_boolean.fixture_toggle"

    static let selection = HomeSelection(
        thermostat: "climate.upstairs_hall",
        humiditySensors: ["sensor.loft_humidity", "sensor.studio_humidity"],
        lock: "lock.side_gate",
        lights: ["light.pantry", "light.gazebo"],
        people: ["person.robin"],
        bedroomTV: "media_player.loft_tv",
        scenes: ["script.film_night", "input_button.test_chime"]
    )

    static func text(_ value: HAValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }

    static func date(_ text: String) -> Date {
        HADate.parse(text)!
    }
}

/// Plays the transcript's server side: frames up to the next client frame are sent as soon as the
/// client reads, and each client frame is checked against the recorded one.
final class TranscriptTransportFactory: HATransportFactory {
    let transport = TranscriptTransport(entries: Transcript.entries)

    func connect(to url: URL) -> any HATransport { transport }
}

final class TranscriptTransport: HATransport {
    private struct State {
        var entries: ArraySlice<Transcript.Entry>
        var mismatches: [String] = []
        var waiter: CheckedContinuation<String, any Error>?
        var closed = false
        var drainWaiters: [CheckedContinuation<Void, Never>] = []

        /// Every recorded frame is used up and the client has read them all.
        var isDrained: Bool { entries.isEmpty && waiter != nil }
    }

    private let state: Mutex<State>

    init(entries: [Transcript.Entry]) {
        state = Mutex(State(entries: entries[...]))
    }

    var mismatches: [String] { state.withLock { $0.mismatches } }
    var remaining: Int { state.withLock { $0.entries.count } }

    func send(_ text: String) async throws {
        let delivery = try state.withLock { state -> (CheckedContinuation<String, any Error>, String)? in
            guard !state.closed else { throw URLError(.networkConnectionLost) }
            guard let next = state.entries.first, next.dir == "out" else {
                state.mismatches.append("unexpected client frame: \(text)")
                return nil
            }
            state.entries.removeFirst()
            if Self.normalized(text) != Self.normalized(next.frame) {
                state.mismatches.append("sent \(text), recorded \(Transcript.text(next.frame))")
            }
            guard let waiter = state.waiter, let reply = state.entries.first, reply.dir == "in" else { return nil }
            state.entries.removeFirst()
            state.waiter = nil
            return (waiter, Transcript.text(reply.frame))
        }
        delivery.map { $0.0.resume(returning: $0.1) }
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            enum Outcome { case frame(String), closed, waiting([CheckedContinuation<Void, Never>]) }
            let outcome = state.withLock { state -> Outcome in
                if state.closed { return .closed }
                if let next = state.entries.first, next.dir == "in" {
                    state.entries.removeFirst()
                    return .frame(Transcript.text(next.frame))
                }
                state.waiter = continuation
                guard state.isDrained else { return .waiting([]) }
                defer { state.drainWaiters = [] }
                return .waiting(state.drainWaiters)
            }
            switch outcome {
            case .frame(let text): continuation.resume(returning: text)
            case .closed: continuation.resume(throwing: URLError(.networkConnectionLost))
            case .waiting(let drained): drained.forEach { $0.resume() }
            }
        }
    }

    func waitUntilDrained() async {
        await withCheckedContinuation { continuation in
            let drained = state.withLock { state -> Bool in
                if state.isDrained { return true }
                state.drainWaiters.append(continuation)
                return false
            }
            if drained { continuation.resume() }
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

    private static func normalized(_ text: String) -> HAValue? {
        (try? JSONDecoder().decode(HAValue.self, from: Data(text.utf8))).map(normalized)
    }

    private static func normalized(_ value: HAValue) -> HAValue {
        guard case .object(var object) = value, object["type"] == .string("auth") else { return value }
        object["access_token"] = .string("REDACTED")
        return .object(object)
    }
}

@Suite("Home Assistant protocol", .timeLimit(.minutes(1)))
@MainActor
struct HomeProtocolTests {
    @Test func decodesEveryRecordedServerFrame() throws {
        let frames = Transcript.serverFrames.map { HAInbound.decode(Transcript.text($0)) }
        #expect(frames.count == 9)

        guard case .authRequired("2026.10.4") = frames[0], case .authOK("2026.10.4") = frames[1] else {
            Issue.record("auth frames: \(frames[0]), \(frames[1])")
            return
        }
        guard case .result(1, .success(nil)) = frames[2] else {
            Issue.record("subscribe result: \(frames[2])")
            return
        }
        guard case .result(2, .success(.states(let states)?)) = frames[3] else {
            Issue.record("get_states result: \(frames[3])")
            return
        }
        #expect(states.count == 15)
        let byID = Dictionary(uniqueKeysWithValues: states.map { ($0.entityID, $0) })

        let climate = try #require(byID["climate.upstairs_hall"])
        #expect(climate.state == "heat")
        #expect(climate.friendlyName == "Upstairs Hall")
        #expect(climate.attributes["current_temperature"]?.number == 74)
        #expect(climate.attributes["temperature"]?.number == 70)
        #expect(climate.attributes["target_temp_high"] == .null)
        #expect(climate.attributes["hvac_modes"]?.array?.compactMap(\.string) == ["off", "heat", "cool", "heat_cool"])
        #expect(climate.lastChanged == Transcript.date("2026-01-21T22:39:29.186261+00:00"))
        #expect(climate.lastUpdated == Transcript.date("2026-01-22T11:57:25.411537+00:00"))

        let humidity = try #require(byID["sensor.loft_humidity"])
        #expect(humidity.numericState == 62)
        #expect(humidity.deviceClass == "humidity")
        #expect(humidity.unit == "%")
        #expect(byID["lock.side_gate"]?.state == "locked")
        #expect(byID["person.robin"]?.state == "not_home")
        #expect(byID["script.film_night"]?.attributes["last_triggered"] == .null)
        #expect(byID["input_button.test_chime"]?.isUnavailable == true)
        #expect(byID[Transcript.toggle]?.state == "off")
        #expect(HomeEntityRole.humidity.candidates(in: states).map(\.entityID) == ["sensor.loft_humidity", "sensor.studio_humidity"])

        guard case .event(1, let on?) = frames[4], case .event(1, let off?) = frames[6] else {
            Issue.record("events: \(frames[4]), \(frames[6])")
            return
        }
        #expect(on.entityID == Transcript.toggle)
        #expect(on.newState?.state == "on")
        #expect(on.timeFired == Transcript.date("2026-01-22T13:23:21.795416+00:00"))
        #expect(off.newState?.state == "off")
        guard case .result(3, .success(.value(let context)?)) = frames[5], case .result(4, .success) = frames[7] else {
            Issue.record("service results: \(frames[5]), \(frames[7])")
            return
        }
        #expect(context["context"]?["id"]?.string?.count == 26)
        guard case .pong(5) = frames[8] else {
            Issue.record("pong: \(frames[8])")
            return
        }
    }

    @Test func clientFramesMatchTheRecordedOnes() {
        let built = [
            HAOutbound.auth(token: "REDACTED"),
            HAOutbound.subscribeStateChanged(id: 1),
            HAOutbound.getStates(id: 2),
            HAOutbound.callService(id: 3, domain: "input_boolean", service: "toggle", entityID: Transcript.toggle),
            HAOutbound.callService(id: 4, domain: "input_boolean", service: "toggle", entityID: Transcript.toggle),
            HAOutbound.ping(id: 5),
        ]
        #expect(built == Transcript.clientFrames.map(Transcript.text))
    }

    @Test func controllerReplaysTheRecordedSession() async throws {
        let server = TranscriptTransportFactory()
        let clock = SteppingClock(now: HomeSample.start)
        let controller = HomeController(
            store: InMemoryKeyValueStore(),
            secrets: InMemorySecretStore(),
            transport: server,
            clock: clock,
            backoff: ReconnectBackoff(jitter: 0)
        )
        controller.calendar = HomeSample.calendar
        controller.now = { clock.now }
        controller.selection = Transcript.selection
        try controller.configure(server: HomeSample.server, token: "replay-token")
        let task = Task { await controller.run() }

        await waitUntil { controller.connection == .connected(version: "2026.10.4") }
        #expect(controller.entities.count == 15)
        let summary = controller.summary
        #expect(summary.climate?.name == "Upstairs Hall")
        #expect(summary.climate?.insideTemperature == 74)
        #expect(summary.climate?.targetTemperature == 70)
        #expect(summary.humidity.map(\.percent) == [62, 57])
        #expect(summary.lock?.state == "locked")
        #expect(summary.lightsOn.map(\.id) == ["light.pantry", "light.gazebo"])
        #expect(summary.people.map(\.isHome) == [false])
        #expect(controller.nudges == [
            HomeNudge(kind: .humidAir, entityIDs: ["sensor.loft_humidity"]),
            HomeNudge(kind: .lightsOnAway, entityIDs: ["light.pantry", "light.gazebo"]),
        ])

        try await controller.callService(domain: "input_boolean", service: "toggle", entityID: Transcript.toggle)
        #expect(controller.entities[Transcript.toggle]?.state == "on")
        #expect(controller.lastEventAt == HomeSample.start)
        try await controller.callService(domain: "input_boolean", service: "toggle", entityID: Transcript.toggle)
        #expect(controller.entities[Transcript.toggle]?.state == "off")

        await clock.waitForSleeper(until: HomeSample.start.addingTimeInterval(30))
        clock.advance(by: 30)
        await server.transport.waitUntilDrained()
        await clock.waitForSleeper(until: HomeSample.start.addingTimeInterval(40))
        clock.advance(by: 10)
        await clock.waitForSleeper(until: HomeSample.start.addingTimeInterval(60), count: 2)
        #expect(controller.connection.isConnected)
        #expect(server.transport.remaining == 0)
        #expect(server.transport.mismatches == [])
        task.cancel()
        await task.value
    }

    @Test func authInvalidCarriesItsMessage() {
        guard case .authInvalid("Invalid access token or password") = HAInbound.decode(#"{"type":"auth_invalid","message":"Invalid access token or password"}"#) else {
            Issue.record("auth_invalid not decoded")
            return
        }
    }

    @Test func failedResultsCarryTheErrorObject() {
        let failed = HAInbound.decode(#"{"id":7,"type":"result","success":false,"error":{"code":"not_found","message":"Service not found."}}"#)
        guard case .result(7, .failure(let error)) = failed else {
            Issue.record("not a failure: \(failed)")
            return
        }
        #expect(error == HAErrorInfo(code: "not_found", message: "Service not found."))

        guard case .result(8, .failure(let bare)) = HAInbound.decode(#"{"id":8,"type":"result","success":false}"#) else {
            Issue.record("bare failure not decoded")
            return
        }
        #expect(bare.code == "unknown_error")
    }

    @Test func anUnreadableResultStillAnswersItsRequest() {
        guard case .result(9, .failure(let error)) = HAInbound.decode(#"{"id":9,"type":"result","success":"yes"}"#) else {
            Issue.record("unreadable result not answered")
            return
        }
        #expect(error.code == "invalid_format")
    }

    @Test func oddFramesAreOther() {
        guard case .other("") = HAInbound.decode("not json"),
              case .other("zeroconf") = HAInbound.decode(#"{"type":"zeroconf"}"#),
              case .other("result") = HAInbound.decode(#"{"type":"result","success":true}"#) else {
            Issue.record("odd frames not passed over")
            return
        }
    }

    @Test func otherEventsHaveNoChange() {
        guard case .event(1, nil) = HAInbound.decode(#"{"id":1,"type":"event","event":{"event_type":"call_service","data":{"domain":"light"}}}"#) else {
            Issue.record("other event not passed over")
            return
        }
    }

    @Test func aNullNewStateIsARemoval() {
        let frame = #"{"id":1,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"light.pantry","old_state":null,"new_state":null},"time_fired":"2026-11-02T20:00:00+00:00"}}"#
        guard case .event(1, let change?) = HAInbound.decode(frame) else {
            Issue.record("removal not decoded")
            return
        }
        #expect(change.entityID == "light.pantry")
        #expect(change.newState == nil)
        #expect(change.timeFired == HomeSample.start)
    }

    @Test func datesParseWithOrWithoutFractionsAndFormatLikeHomeAssistant() throws {
        #expect(HADate.parse("2026-11-02T20:00:00+00:00") == HomeSample.start)
        #expect(HADate.parse("2026-11-02T14:00:00-06:00") == HomeSample.start)
        #expect(HADate.parse("2026-11-02T20:00:00Z") == HomeSample.start)
        let precise = try #require(HADate.parse("2026-11-02T20:00:00.123456+00:00"))
        #expect(abs(precise.timeIntervalSince(HomeSample.start) - 0.123456) < 0.000_001)
        #expect(HADate.parse("yesterday") == nil)
        #expect(HADate.format(HomeSample.start.addingTimeInterval(0.25)) == "2026-11-02T20:00:00.250000+00:00")
        let entity = HomeSample.entity("light.pantry", "on", name: "Pantry")
        let decoded = HAInbound.decode(HAOutbound.encode(["id": .number(1), "type": .string("result"), "success": .bool(true), "result": .array([entity.wireValue])]))
        guard case .result(1, .success(.states(let states)?)) = decoded else {
            Issue.record("round trip failed")
            return
        }
        #expect(states == [entity])
    }

    @Test func urlSessionTransportFailsOnceClosed() async {
        let transport = URLSessionHATransport(url: URL(string: "ws://127.0.0.1:9/api/websocket")!)
        #expect(transport.maximumMessageSize == 32 * 1024 * 1024)
        transport.close()
        transport.close()
        await #expect(throws: URLError.self) { _ = try await transport.receive() }
        await #expect(throws: URLError.self) { try await transport.send("{}") }
    }
}
