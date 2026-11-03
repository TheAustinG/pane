import Foundation
import Testing
@testable import PaneCore

private let start = HomeSample.start

@Suite("Home controller", .timeLimit(.minutes(1)))
@MainActor
struct HomeControllerTests {
    @Test func connectsSubscribesBeforeTheSnapshotAndShowsEntities() async {
        let harness = HomeHarness()
        await harness.connect()
        let controller = harness.controller

        #expect(controller.connection == .connected(version: FixtureHATransportFactory.defaultVersion))
        #expect(controller.connectionHistory == [.connecting, .connected(version: FixtureHATransportFactory.defaultVersion)])
        #expect(controller.entities == HomeSample.byID)
        #expect(controller.reconnectCount == 0)
        #expect(harness.factory.connectedURLs == [URL(string: "ws://ha.fixture.invalid:8123/api/websocket")!])

        let frames = harness.received
        #expect(frames.map { $0["type"]?.string } == ["auth", "subscribe_events", "get_states"])
        #expect(frames.dropFirst().map { $0["id"]?.int } == [1, 2])
        #expect(frames[1]["event_type"]?.string == "state_changed")
        await harness.stop()
    }

    @Test func eventsUpdateAndRemoveEntities() async {
        let harness = HomeHarness()
        await harness.connect()
        let controller = harness.controller
        #expect(controller.lastEventAt == nil)

        harness.clock.advance(by: 5)
        harness.fixture.setState("light.pantry", to: "on", attributes: ["friendly_name": .string("Pantry"), "brightness": .number(128)])
        await waitUntil { controller.entities["light.pantry"]?.state == "on" }
        #expect(controller.entities["light.pantry"]?.attributes["brightness"] == .number(128))
        #expect(controller.entities["light.pantry"]?.lastChanged == start.addingTimeInterval(5))
        #expect(controller.lastEventAt == start.addingTimeInterval(5))

        harness.fixture.setState("sensor.new_humidity", to: "40")
        await waitUntil { controller.entities["sensor.new_humidity"] != nil }

        harness.fixture.removeEntity("light.gazebo")
        await waitUntil { controller.entities["light.gazebo"] == nil }
        #expect(controller.entities.count == HomeSample.entities.count)
        await harness.stop()
    }

    @Test func callServiceSucceedsAndTheStateFollows() async throws {
        let harness = HomeHarness()
        await harness.connect()
        let controller = harness.controller

        try await controller.callService(domain: "input_boolean", service: "toggle", entityID: "input_boolean.fixture_toggle")
        #expect(harness.fixture.serviceCalls == [.init(domain: "input_boolean", service: "toggle", entityIDs: ["input_boolean.fixture_toggle"])])
        // The fixture, like Home Assistant, sends the state change before the result.
        #expect(controller.entities["input_boolean.fixture_toggle"]?.state == "on")

        let call = try #require(harness.received.last)
        #expect(call["type"]?.string == "call_service")
        #expect(call["id"]?.int == 3)
        #expect(call["target"]?["entity_id"]?.string == "input_boolean.fixture_toggle")
        await harness.stop()
    }

    @Test func callServiceFailureCarriesTheServerError() async {
        let harness = HomeHarness()
        await harness.connect()
        harness.fixture.failCalls(to: "light", "turn_on", code: "home_assistant_error", message: "Device offline")

        do {
            try await harness.controller.callService(domain: "light", service: "turn_on", entityID: "light.pantry")
            Issue.record("expected a failure")
        } catch {
            #expect(error as? HomeServiceError == .failed(code: "home_assistant_error", message: "Device offline"))
            #expect(!String(describing: error).contains(HomeSample.token))
            #expect(error.localizedDescription == "Device offline")
        }
        #expect(harness.controller.connection.isConnected)
        await harness.stop()
    }

    @Test func unknownServiceIsRejected() async {
        let harness = HomeHarness()
        await harness.connect()
        await #expect(throws: HomeServiceError.failed(code: "not_found", message: "Service light.blink not found.")) {
            try await harness.controller.callService(domain: "light", service: "blink", entityID: "light.pantry")
        }
        await harness.stop()
    }

    @Test func callServiceTimesOutButKeepsTheConnection() async {
        let harness = HomeHarness()
        await harness.connect()
        harness.fixture.ignoresServiceCalls = true
        let controller = harness.controller

        let call = Task { try await controller.callService(domain: "light", service: "turn_on", entityID: "light.pantry") }
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(HomeController.requestTimeout))
        harness.clock.advance(by: HomeController.requestTimeout)
        await #expect(throws: HomeServiceError.timeout) { try await call.value }
        #expect(controller.connection.isConnected)
        await harness.stop()
    }

    @Test func callServiceNeedsAConnection() async {
        let harness = HomeHarness()
        await #expect(throws: HomeServiceError.notConnected) {
            try await harness.controller.callService(domain: "light", service: "turn_on", entityID: "light.pantry")
        }
        #expect(harness.fixture.connectionsOpened == 0)
    }

    @Test func activateSceneMapsEachDomainToItsService() async throws {
        let harness = HomeHarness()
        await harness.connect()
        let controller = harness.controller

        try await controller.activateScene("scene.good_night")
        try await controller.activateScene("script.film_night")
        try await controller.activateScene("input_button.test_chime")
        await #expect(throws: HomeServiceError.unsupportedDomain("light")) {
            try await controller.activateScene("light.pantry")
        }
        #expect(harness.fixture.serviceCalls == [
            .init(domain: "scene", service: "turn_on", entityIDs: ["scene.good_night"]),
            .init(domain: "script", service: "turn_on", entityIDs: ["script.film_night"]),
            .init(domain: "input_button", service: "press", entityIDs: ["input_button.test_chime"]),
        ])
        #expect(controller.entities["script.film_night"]?.attributes["last_triggered"]?.string == "2026-11-02T20:00:00.000000+00:00")
        #expect(controller.entities["input_button.test_chime"]?.state == "2026-11-02T20:00:00.000000+00:00")
        await harness.stop()
    }

    @Test func settingsPersistAndTheTokenStaysInTheSecretStore() async throws {
        let store = InMemoryKeyValueStore()
        let secrets = InMemorySecretStore()
        let first = HomeHarness(token: "  \(HomeSample.token)\n", store: store, secrets: secrets).controller
        first.selection = HomeSample.selection
        first.nudgePreferences.setEnabled(false, .bedroomTVLate)

        #expect(try secrets.string(for: .homeAssistantToken) == HomeSample.token)
        for key in HomeController.Keys.all {
            let data = try #require(store.data(forKey: key))
            #expect(!String(decoding: data, as: UTF8.self).contains(HomeSample.token))
        }
        #expect(store.data(forKey: "home.server").map { String(decoding: $0, as: UTF8.self) } == "http://ha.fixture.invalid:8123")

        let second = HomeController(store: store, secrets: secrets, transport: FixtureHATransportFactory())
        #expect(second.server == HomeSample.server)
        #expect(second.selection == HomeSample.selection)
        #expect(second.nudgePreferences == HomeNudgePreferences(disabled: [.bedroomTVLate]))
        #expect(second.hasToken)
        #expect(second.connection == .connecting)
    }

    @Test func forgetClearsEverything() async throws {
        let harness = HomeHarness()
        await harness.connect()
        let controller = harness.controller
        controller.selection = HomeSample.selection
        controller.nudgePreferences.setEnabled(false, .dryAir)
        controller.debugOverrides = ["light.pantry": HomeSample.entity("light.pantry", "on")]

        try controller.forget()
        #expect(controller.server == nil)
        #expect(!controller.hasToken)
        #expect(controller.selection == .empty)
        #expect(controller.nudgePreferences == HomeNudgePreferences())
        #expect(controller.entities.isEmpty)
        #expect(controller.nudges.isEmpty)
        #expect(controller.connection == .notConfigured)
        for key in HomeController.Keys.all {
            #expect(harness.store.data(forKey: key) == nil)
        }
        await waitUntil { controller.connection == .notConfigured }
        await harness.fixture.waitUntil { $0.openConnections == 0 }
        #expect(harness.fixture.connectionsOpened == 1)
        await harness.stop()
    }

    @Test func resetClearsTheStoreAndTheToken() throws {
        let store = InMemoryKeyValueStore()
        let secrets = InMemorySecretStore()
        let controller = HomeHarness(store: store, secrets: secrets).controller
        controller.selection = HomeSample.selection
        controller.nudgePreferences.setEnabled(false, .humidAir)

        HomeController.reset(store: store, secrets: secrets)
        for key in HomeController.Keys.all {
            #expect(store.data(forKey: key) == nil)
        }
        #expect(try secrets.string(for: .homeAssistantToken) == nil)
        let fresh = HomeController(store: store, secrets: secrets, transport: FixtureHATransportFactory())
        #expect(fresh.server == nil)
        #expect(fresh.selection == .empty)
        #expect(fresh.connection == .notConfigured)
    }

    @Test func configuringAnotherServerReconnectsToIt() async throws {
        let harness = HomeHarness()
        await harness.connect()
        let controller = harness.controller

        try controller.configure(server: HomeSample.otherServer, token: HomeSample.token)
        #expect(controller.entities.isEmpty)
        await waitUntil { controller.connection.isConnected && !controller.entities.isEmpty }
        #expect(harness.factory.connectedURLs.map(\.absoluteString) == [
            "ws://ha.fixture.invalid:8123/api/websocket",
            "wss://other.fixture.invalid/api/websocket",
        ])
        #expect(controller.server == HomeSample.otherServer)
        #expect(harness.fixture.snapshot.openConnections == 1)
        #expect(!controller.connectionHistory.contains { if case .disconnected = $0 { true } else { false } })
        await harness.stop()
    }

    @Test func notConfiguredUntilAServerAndTokenArrive() async throws {
        let harness = HomeHarness(configured: false)
        let controller = harness.controller
        #expect(controller.connection == .notConfigured)
        harness.launch()
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(HomeController.idleInterval))
        #expect(controller.connection == .notConfigured)
        #expect(harness.fixture.connectionsOpened == 0)

        try controller.configure(server: HomeSample.server, token: " ")
        #expect(controller.connection == .notConfigured)

        try controller.configure(server: HomeSample.server, token: HomeSample.token)
        await waitUntil { controller.connection.isConnected }
        #expect(harness.fixture.connectionsOpened == 1)
        await harness.stop()
    }

    @Test func debugOverridesWinPerEntity() async {
        let harness = HomeHarness()
        await harness.connect()
        let controller = harness.controller
        let override = HomeSample.entity("light.pantry", "on", name: "Pantry")

        controller.debugOverrides = ["light.pantry": override, "sensor.debug_only": HomeSample.humidity("sensor.debug_only", "20")]
        #expect(controller.entities["light.pantry"] == override)
        #expect(controller.entities["sensor.debug_only"]?.state == "20")

        harness.fixture.setState("light.pantry", to: "off", attributes: ["friendly_name": .string("Live")])
        harness.fixture.setState("light.gazebo", to: "on")
        await waitUntil { controller.entities["light.gazebo"]?.state == "on" }
        #expect(controller.entities["light.pantry"] == override)

        controller.debugOverrides = [:]
        #expect(controller.entities["light.pantry"]?.friendlyName == "Live")
        #expect(controller.entities["sensor.debug_only"] == nil)
        await harness.stop()
    }

    @Test func nudgesFollowEntitiesOverridesSelectionAndPreferences() async {
        let harness = HomeHarness()
        await harness.connect()
        let controller = harness.controller
        #expect(controller.nudges.isEmpty)

        controller.selection = HomeSample.selection
        harness.fixture.setState("sensor.loft_humidity", to: "30")
        await waitUntil { !controller.nudges.isEmpty }
        #expect(controller.nudges == [HomeNudge(kind: .dryAir, entityIDs: ["sensor.loft_humidity"])])
        #expect(controller.summary.nudge(.dryAir) != nil)

        harness.fixture.setState("sensor.loft_humidity", to: "36")
        await waitUntil { controller.entities["sensor.loft_humidity"]?.state == "36" }
        #expect(controller.nudges.map(\.kind) == [.dryAir])
        harness.fixture.setState("sensor.loft_humidity", to: "37")
        await waitUntil { controller.nudges.isEmpty }

        controller.debugOverrides = ["sensor.studio_humidity": HomeSample.humidity("sensor.studio_humidity", "70")]
        #expect(controller.nudges == [HomeNudge(kind: .humidAir, entityIDs: ["sensor.studio_humidity"])])
        controller.nudgePreferences.setEnabled(false, .humidAir)
        #expect(controller.nudges.isEmpty)
        controller.nudgePreferences.setEnabled(true, .humidAir)
        #expect(controller.nudges.map(\.kind) == [.humidAir])
        controller.selection.setEntityIDs([], for: .humidity)
        #expect(controller.nudges.isEmpty)
        await harness.stop()
    }

    @Test func timeOfDayNudgesTickOnAppTime() async {
        let harness = HomeHarness(configured: false)
        let controller = harness.controller
        controller.selection = HomeSample.selection
        var appTime = WeatherFixture.local(2026, 11, 2, 21, 59)
        controller.now = { appTime }
        controller.debugOverrides = ["lock.side_gate": HomeSample.entity("lock.side_gate", "unlocked")]
        #expect(controller.nudges.isEmpty)
        harness.launch()

        appTime = WeatherFixture.local(2026, 11, 2, 22)
        #expect(controller.nudges.isEmpty)
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(HomeController.nudgeInterval))
        harness.clock.advance(by: HomeController.nudgeInterval)
        await waitUntil { !controller.nudges.isEmpty }
        #expect(controller.nudges == [HomeNudge(kind: .doorUnlockedLate, entityIDs: ["lock.side_gate"])])

        appTime = WeatherFixture.local(2026, 11, 3, 6)
        controller.now = { appTime }
        #expect(controller.nudges.isEmpty)
        await harness.stop()
    }

    @Test func previewRunsTheRealPathOverTheFixture() async throws {
        let controller = HomeController.preview(entities: HomeSample.entities, selection: HomeSample.selection)
        let fixture = try #require(controller.fixture)
        #expect(controller.entities == HomeSample.byID)
        #expect(controller.selection == HomeSample.selection)
        #expect(controller.server?.address == "http://fixture.invalid")
        #expect(controller.connection == .connecting)

        let task = Task { await controller.run() }
        await waitUntil { controller.connection.isConnected }
        fixture.setState("light.pantry", to: "on")
        await waitUntil { controller.entities["light.pantry"]?.state == "on" }
        try await controller.activateScene("script.film_night")
        #expect(fixture.serviceCalls.map(\.service) == ["turn_on"])
        task.cancel()
        await task.value
    }

    @Test func cancellingRunClosesTheSocket() async {
        let harness = HomeHarness()
        await harness.connect()
        await harness.stop()
        #expect(harness.fixture.snapshot.openConnections == 0)
        #expect(harness.controller.connection == .disconnected(since: start, retryAt: nil))
    }
}
