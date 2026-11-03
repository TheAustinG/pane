import Foundation
import Testing
@testable import PaneCore

private let start = HomeSample.start

private func fixture(expectedToken: String? = HomeSample.token) -> FixtureHATransportFactory {
    FixtureHATransportFactory(entities: HomeSample.entities, expectedToken: expectedToken, now: { start })
}

private func next(_ transport: any HATransport) async throws -> HAValue {
    try JSONDecoder().decode(HAValue.self, from: Data(try await transport.receive().utf8))
}

private func open(_ server: FixtureHATransportFactory, token: String = HomeSample.token) async throws -> any HATransport {
    let transport = server.connect(to: HomeSample.server.webSocketURL)
    _ = try await transport.receive()
    try await transport.send(HAOutbound.auth(token: token))
    _ = try await transport.receive()
    return transport
}

private func send(_ transport: any HATransport, _ object: [String: HAValue]) async throws {
    try await transport.send(HAOutbound.encode(object))
}

@Suite("Fixture Home Assistant", .timeLimit(.minutes(1)))
struct HomeFixtureTests {
    @Test func authenticatesLikeHomeAssistant() async throws {
        let server = fixture()
        let transport = server.connect(to: HomeSample.server.webSocketURL)
        let hello = try await next(transport)
        #expect(hello == .object(["type": .string("auth_required"), "ha_version": .string(FixtureHATransportFactory.defaultVersion)]))
        try await transport.send(HAOutbound.auth(token: HomeSample.token))
        #expect(try await next(transport)["type"]?.string == "auth_ok")
        #expect(!server.snapshot.received.contains { $0.contains(HomeSample.token) })
    }

    @Test func aWrongTokenGetsAuthInvalidThenTheSocketCloses() async throws {
        let server = fixture()
        let transport = server.connect(to: HomeSample.server.webSocketURL)
        _ = try await transport.receive()
        try await transport.send(HAOutbound.auth(token: "wrong"))
        #expect(try await next(transport)["type"]?.string == "auth_invalid")
        await #expect(throws: URLError.self) { _ = try await transport.receive() }
        #expect(server.snapshot.openConnections == 0)
    }

    @Test func idsMustIncrease() async throws {
        let transport = try await open(fixture())
        try await transport.send(HAOutbound.getStates(id: 2))
        let states = try await next(transport)
        #expect(states["result"]?.array?.count == HomeSample.entities.count)
        try await transport.send(HAOutbound.ping(id: 2))
        let reused = try await next(transport)
        #expect(reused["success"] == .bool(false))
        #expect(reused["error"]?["code"]?.string == "id_reuse")
        try await transport.send(HAOutbound.ping(id: 3))
        #expect(try await next(transport) == .object(["id": .number(3), "type": .string("pong")]))
    }

    @Test func togglesEmitStateChangedToEverySubscriberBeforeTheResult() async throws {
        let server = fixture()
        let first = try await open(server)
        let second = try await open(server)
        try await first.send(HAOutbound.subscribeStateChanged(id: 1))
        _ = try await next(first)
        try await second.send(HAOutbound.subscribeStateChanged(id: 5))
        _ = try await next(second)

        try await first.send(HAOutbound.callService(id: 2, domain: "input_boolean", service: "toggle", entityID: "input_boolean.fixture_toggle"))
        let event = try await next(first)
        #expect(event["id"] == .number(1))
        #expect(event["event"]?["event_type"]?.string == "state_changed")
        #expect(event["event"]?["data"]?["old_state"]?["state"]?.string == "off")
        #expect(event["event"]?["data"]?["new_state"]?["state"]?.string == "on")
        let result = try await next(first)
        #expect(result["id"] == .number(2))
        #expect(result["success"] == .bool(true))
        #expect(result["result"]?["context"]?["id"]?.string?.count == 26)
        #expect(try await next(second)["id"] == .number(5))

        #expect(server.entity("input_boolean.fixture_toggle")?.state == "on")
        #expect(server.serviceCalls == [.init(domain: "input_boolean", service: "toggle", entityIDs: ["input_boolean.fixture_toggle"])])
    }

    @Test func aCallThatChangesNothingSendsNoEvent() async throws {
        let transport = try await open(fixture())
        try await transport.send(HAOutbound.subscribeStateChanged(id: 1))
        _ = try await next(transport)
        try await transport.send(HAOutbound.callService(id: 2, domain: "light", service: "turn_off", entityID: "light.pantry"))
        let reply = try await next(transport)
        #expect(reply["type"]?.string == "result")
        #expect(reply["id"] == .number(2))
    }

    @Test func scriptsAndScenesStampLastTriggered() async throws {
        let server = fixture()
        let transport = try await open(server)
        try await transport.send(HAOutbound.callService(id: 1, domain: "script", service: "turn_on", entityID: "script.film_night"))
        try await transport.send(HAOutbound.callService(id: 2, domain: "scene", service: "turn_on", entityID: "scene.good_night"))
        _ = try await next(transport)
        _ = try await next(transport)
        let stamp = HADate.format(start)
        #expect(server.entity("script.film_night")?.attributes["last_triggered"] == .string(stamp))
        #expect(server.entity("script.film_night")?.state == "off")
        #expect(server.entity("scene.good_night")?.state == stamp)
        #expect(server.entity("scene.good_night")?.attributes["last_triggered"] == .string(stamp))
    }

    @Test func unknownServicesAndCommandsAreRefused() async throws {
        let server = fixture()
        let transport = try await open(server)
        try await transport.send(HAOutbound.callService(id: 1, domain: "lock", service: "unlock", entityID: "lock.side_gate"))
        #expect(try await next(transport)["error"]?["code"]?.string == "not_found")
        #expect(server.entity("lock.side_gate")?.state == "locked")
        try await send(transport, ["id": .number(2), "type": .string("render_template")])
        #expect(try await next(transport)["error"]?["code"]?.string == "unknown_command")
    }

    @Test func configuredFailuresAndSilenceAnswerAsTold() async throws {
        let server = fixture()
        let transport = try await open(server)
        server.failCalls(to: "light", "turn_on", code: "home_assistant_error", message: "Offline")
        try await transport.send(HAOutbound.callService(id: 1, domain: "light", service: "turn_on", entityID: "light.pantry"))
        let failed = try await next(transport)
        #expect(failed["error"] == .object(["code": .string("home_assistant_error"), "message": .string("Offline")]))
        server.clearFailures()

        server.ignoresServiceCalls = true
        server.respondsToPings = false
        try await transport.send(HAOutbound.callService(id: 2, domain: "light", service: "turn_on", entityID: "light.pantry"))
        try await transport.send(HAOutbound.ping(id: 3))
        try await transport.send(HAOutbound.getStates(id: 4))
        #expect(try await next(transport)["id"] == .number(4))
        #expect(server.serviceCalls.count == 2)
        #expect(server.entity("light.pantry")?.state == "off")
    }

    @Test func helpersSetAndRemoveStatesWithEvents() async throws {
        let server = fixture()
        let transport = try await open(server)
        try await transport.send(HAOutbound.subscribeStateChanged(id: 1))
        _ = try await next(transport)

        server.setState("sensor.new", to: "12", attributes: ["unit_of_measurement": .string("%")])
        let created = try await next(transport)
        #expect(created["event"]?["data"]?["old_state"] == .null)
        #expect(created["event"]?["data"]?["new_state"]?["attributes"]?["unit_of_measurement"]?.string == "%")

        server.removeEntity("sensor.new")
        let removed = try await next(transport)
        #expect(removed["event"]?["data"]?["new_state"] == .null)
        #expect(server.entity("sensor.new") == nil)

        server.setEntity(HomeSample.entity("light.pantry", "on", name: "Pantry"))
        #expect(try await next(transport)["event"]?["data"]?["new_state"]?["state"]?.string == "on")
        #expect(server.entities.count == HomeSample.entities.count)
    }

    @Test func refusedDroppedAndClosedConnectionsFail() async throws {
        let server = fixture()
        server.refusesConnections = true
        let refused = server.connect(to: HomeSample.server.webSocketURL)
        await #expect(throws: URLError(.cannotConnectToHost)) { _ = try await refused.receive() }
        await #expect(throws: URLError(.cannotConnectToHost)) { try await refused.send("{}") }
        server.refusesConnections = false

        let dropped = try await open(server)
        let closed = try await open(server)
        let waiting = Task { try await dropped.receive() }
        server.dropConnections()
        await #expect(throws: URLError.self) { _ = try await waiting.value }
        closed.close()
        await #expect(throws: URLError.self) { _ = try await closed.receive() }
        #expect(server.snapshot.openConnections == 0)
        #expect(server.connectionsOpened == 3)
    }
}
