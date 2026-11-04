import Foundation
import Testing
@testable import PaneCore

@Suite("Home summary")
struct HomeSummaryTests {
    @Test func buildsTheCardFromTheSelectedEntities() {
        var entities = HomeSample.byID
        entities["climate.den"] = HomeSample.entity("climate.den", "heat_cool", [
            "current_temperature": .number(71.5),
            "hvac_action": .string("heating"),
            "target_temp_low": .number(66),
            "target_temp_high": .string("76"),
        ], name: "Den")
        entities["light.gazebo"] = HomeSample.entity("light.gazebo", "on", name: "Gazebo")
        entities["person.kit"] = HomeSample.entity("person.kit", "not_home", name: "Kit")
        let nudges = [HomeNudge(kind: .humidAir, entityIDs: ["sensor.studio_humidity"])]

        let summary = HomeSummary.make(entities: entities, selection: HomeSample.selection, nudges: nudges)
        #expect(summary.climate == HomeSummary.Climate(
            name: "Den",
            insideTemperature: 71.5,
            action: "heating",
            mode: "heat_cool",
            targetTemperature: nil,
            targetLow: 66,
            targetHigh: 76,
            isUnavailable: false
        ))
        #expect(summary.humidity.map(\.name) == ["sensor.loft_humidity", "sensor.studio_humidity"])
        #expect(summary.humidity.map(\.percent) == [45, 50])
        #expect(summary.lock == HomeSummary.Lock(name: "Side Gate", state: "locked", since: HomeSample.start))
        #expect(summary.lights.map(\.isOn) == [false, true])
        #expect(summary.lightsOn.map(\.name) == ["Gazebo"])
        #expect(summary.people.map(\.isHome) == [true, false])
        #expect(summary.nudge(.humidAir) == nudges.first)
        #expect(summary.nudge(.dryAir) == nil)
    }

    @Test func missingEntitiesAreLeftOutAndUnavailableOnesShowNoValue() {
        var entities = HomeSample.byID
        entities["sensor.loft_humidity"] = HomeSample.humidity("sensor.loft_humidity", "unavailable")
        entities["climate.den"] = HomeSample.entity("climate.den", "unavailable")
        entities["lock.side_gate"] = nil
        var selection = HomeSample.selection
        selection.lights = ["light.renamed", "light.pantry"]

        let summary = HomeSummary.make(entities: entities, selection: selection, nudges: [])
        #expect(summary.humidity.map(\.percent) == [nil, 50])
        #expect(summary.climate?.isUnavailable == true)
        #expect(summary.climate?.insideTemperature == nil)
        #expect(summary.lock == nil)
        #expect(summary.lights.map(\.id) == ["light.pantry"])
    }

    @Test func unavailableTrackersAreNotCountedAsAway() {
        var entities = HomeSample.byID
        entities["person.kit"] = HomeSample.entity("person.kit", "unavailable", name: "Kit")
        let summary = HomeSummary.make(entities: entities, selection: HomeSample.selection, nudges: [])
        #expect(summary.people.map(\.isHome) == [true])
        #expect(!summary.people.contains { $0.id == "person.kit" })
    }

    @Test func anEmptySelectionShowsNothing() {
        let summary = HomeSummary.make(entities: HomeSample.byID, selection: .empty, nudges: [])
        #expect(summary == HomeSummary())
    }
}

@Suite("Home selection")
struct HomeSelectionTests {
    @Test func rolesReadAndWriteTheirSlots() {
        var selection = HomeSelection.empty
        #expect(selection.isEmpty)
        for role in HomeEntityRole.allCases {
            selection.setEntityIDs(["\(role.rawValue).a", "\(role.rawValue).b"], for: role)
        }
        for role in HomeEntityRole.allCases {
            let expected = role.allowsMany ? ["\(role.rawValue).a", "\(role.rawValue).b"] : ["\(role.rawValue).a"]
            #expect(selection.entityIDs(for: role) == expected)
        }
        #expect(selection.thermostat == "thermostat.a")
        #expect(selection.bedroomTV == "bedroomTV.a")
        #expect(!selection.isEmpty)

        selection.setEntityIDs([], for: .lock)
        #expect(selection.lock == nil)
        #expect(selection.entityIDs(for: .lock).isEmpty)
    }

    @Test func droppingTheGoodnightSceneClearsIt() {
        var selection = HomeSample.selection
        selection.goodnightScene = "script.film_night"
        selection.setEntityIDs(["script.film_night", "input_button.test_chime"], for: .scenes)
        #expect(selection.goodnightScene == "script.film_night")
        selection.setEntityIDs(["input_button.test_chime"], for: .scenes)
        #expect(selection.goodnightScene == nil)
    }

    @Test func goodnightIsTheChosenSceneElseOneNamedGoodnight() {
        let entities = HomeSample.byID
        var selection = HomeSample.selection
        #expect(selection.goodnightEntityID(in: entities) == "scene.good_night")

        selection.goodnightScene = "script.film_night"
        #expect(selection.goodnightEntityID(in: entities) == "script.film_night")

        selection.goodnightScene = "scene.not_a_button"
        #expect(selection.goodnightEntityID(in: entities) == "scene.good_night")

        selection = HomeSelection(scenes: ["script.film_night", "script.bedtime"])
        let named = ["script.bedtime": HomeSample.entity("script.bedtime", "off", name: "Goodnight")]
        #expect(selection.goodnightEntityID(in: named) == "script.bedtime")
        #expect(HomeSelection(scenes: ["scene.goodnight"]).goodnightEntityID(in: [:]) == "scene.goodnight")
        #expect(HomeSelection(scenes: ["script.film_night"]).goodnightEntityID(in: entities) == nil)
    }

    @Test func candidatesFilterByDomainAndSortByName() {
        let entities = HomeSample.entities + [
            HomeSample.entity("sensor.power", "120", ["device_class": .string("power")]),
            HomeSample.entity("sensor.aaa_humidity", "40", ["device_class": .string("humidity")], name: "Attic Humidity"),
            HomeSample.entity("device_tracker.robin_phone", "home", name: "Robin Phone"),
        ]
        #expect(HomeEntityRole.humidity.candidates(in: entities).map(\.entityID) == [
            "sensor.aaa_humidity", "sensor.loft_humidity", "sensor.studio_humidity",
        ])
        #expect(HomeEntityRole.lights.candidates(in: entities).map(\.friendlyName) == ["Fixture Toggle", "Gazebo", "Pantry", "Reading Nook"])
        #expect(HomeEntityRole.people.candidates(in: entities).map(\.friendlyName) == ["Kit", "Robin", "Robin Phone"])
        #expect(HomeEntityRole.scenes.candidates(in: entities).map(\.entityID) == ["script.film_night", "scene.good_night", "input_button.test_chime"])
        #expect(HomeEntityRole.thermostat.candidates(in: entities).map(\.entityID) == ["climate.den"])
    }

    @Test func roundTripsThroughJSON() throws {
        var selection = HomeSample.selection
        selection.goodnightScene = "scene.good_night"
        let data = try JSONEncoder().encode(selection)
        #expect(try JSONDecoder().decode(HomeSelection.self, from: data) == selection)
    }
}

@Suite("Home server address")
struct HomeServerTests {
    @Test(arguments: [
        ("homeassistant.local:8123", "http://homeassistant.local:8123", "ws://homeassistant.local:8123/api/websocket"),
        ("  ha.fixture.invalid:8123 \n", "http://ha.fixture.invalid:8123", "ws://ha.fixture.invalid:8123/api/websocket"),
        ("https://ha.example.com/", "https://ha.example.com", "wss://ha.example.com/api/websocket"),
        ("HTTP://ha.example.com:8123/lovelace/0?edit=1#top", "http://ha.example.com:8123", "ws://ha.example.com:8123/api/websocket"),
        ("http://[2001:db8::1]:8123", "http://[2001:db8::1]:8123", "ws://[2001:db8::1]:8123/api/websocket"),
    ])
    func parsesTypedAddresses(_ typed: String, _ address: String, _ webSocket: String) throws {
        let server = try #require(HomeServer(address: typed))
        #expect(server.address == address)
        #expect(server.webSocketURL.absoluteString == webSocket)
    }

    @Test(arguments: ["", "   ", "http://", "ftp://ha.example.com", "ws://ha.example.com", "http://ha.example.com:port"])
    func rejectsWhatIsNotAnAddress(_ typed: String) {
        #expect(HomeServer(address: typed) == nil)
    }

    @Test func connectionStates() {
        #expect(HomeConnection.connected(version: "1").isConnected)
        #expect(!HomeConnection.connecting.isConnected)
        #expect(!HomeConnection.authFailed.isConnected)
        #expect(!HomeConnection.disconnected(since: HomeSample.start, retryAt: nil).isConnected)
    }
}

@Suite("Home snapshot merge")
struct HomeSnapshotMergeTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func entity(_ id: String, _ state: String, at date: Date?) -> HAEntity {
        HAEntity(entityID: id, state: state, lastChanged: date, lastUpdated: date)
    }

    @Test func newerEarlyChangesWinAndOlderOnesAreDropped() {
        let snapshot = [entity("light.a", "off", at: t0), entity("light.b", "off", at: t0)]
        let early = [
            HAStateChange(entityID: "light.a", newState: entity("light.a", "on", at: t0 + 5), timeFired: t0 + 5),
            HAStateChange(entityID: "light.b", newState: entity("light.b", "on", at: t0 - 5), timeFired: t0 - 5),
        ]
        let merged = HomeController.merge(snapshot: snapshot, earlyChanges: early)
        #expect(merged["light.a"]?.state == "on")
        #expect(merged["light.b"]?.state == "off")
    }

    @Test func anEntityCreatedDuringTheSnapshotIsKept() {
        let early = [HAStateChange(entityID: "lock.new", newState: entity("lock.new", "locked", at: t0), timeFired: t0)]
        let merged = HomeController.merge(snapshot: [entity("light.a", "off", at: t0)], earlyChanges: early)
        #expect(merged["lock.new"]?.state == "locked")
    }

    @Test func aRemovalOfAnUnknownEntityChangesNothing() {
        let early = [HAStateChange(entityID: "lock.gone", newState: nil, timeFired: t0)]
        let merged = HomeController.merge(snapshot: [entity("light.a", "off", at: t0)], earlyChanges: early)
        #expect(merged.keys.sorted() == ["light.a"])
    }

    @Test func aSnapshotEntryWithoutATimestampTakesTheEarlyChange() {
        let early = [HAStateChange(entityID: "light.a", newState: entity("light.a", "on", at: t0), timeFired: t0)]
        let merged = HomeController.merge(snapshot: [entity("light.a", "off", at: nil)], earlyChanges: early)
        #expect(merged["light.a"]?.state == "on")
    }
}
