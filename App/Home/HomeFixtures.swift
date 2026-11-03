#if DEBUG
import Foundation
import PaneCore

/// Sample entities for repeatable Home card states. Invented names and ids only.
enum HomeFixtures {
    static var entities: [HAEntity] {
        let lockChanged = Calendar.current.date(bySettingHour: 15, minute: 58, second: 0, of: .now)
        return [
            HAEntity(entityID: "climate.sample_thermostat", state: "heat", attributes: [
                "friendly_name": .string("Thermostat"),
                "current_temperature": .number(70),
                "temperature": .number(69),
                "hvac_action": .string("heating"),
            ]),
            humidity("sensor.sample_hall_humidity", "Hall Humidity", 42),
            humidity("sensor.sample_bedroom_humidity", "Bedroom Humidity", 44),
            HAEntity(entityID: "sensor.sample_outdoor_temperature", state: "48", attributes: [
                "friendly_name": .string("Outdoor Temperature"),
                "device_class": .string("temperature"),
                "unit_of_measurement": .string("°F"),
            ]),
            HAEntity(entityID: "lock.sample_front_door", state: "locked", attributes: [
                "friendly_name": .string("Front Door"),
            ], lastChanged: lockChanged),
            light("light.sample_kitchen", "Kitchen", on: true),
            light("light.sample_living_room", "Living Room", on: true),
            light("light.sample_hall", "Hall", on: true),
            light("light.sample_porch", "Porch", on: false),
            light("light.sample_garage", "Garage", on: false),
            person("person.sample_alex", "Alex", home: true),
            person("person.sample_sam", "Sam", home: true),
            HAEntity(entityID: "media_player.sample_bedroom_tv", state: "off", attributes: ["friendly_name": .string("Bedroom TV")]),
            HAEntity(entityID: "media_player.sample_living_room_tv", state: "off", attributes: ["friendly_name": .string("Living Room TV")]),
            HAEntity(entityID: "scene.sample_goodnight", state: "unknown", attributes: ["friendly_name": .string("Goodnight")]),
            HAEntity(entityID: "scene.sample_movie", state: "unknown", attributes: ["friendly_name": .string("Movie")]),
            HAEntity(entityID: "script.sample_morning", state: "off", attributes: ["friendly_name": .string("Morning")]),
            HAEntity(entityID: "scene.sample_dinner", state: "unknown", attributes: ["friendly_name": .string("Dinner")]),
        ]
    }

    static let selection = HomeSelection(
        thermostat: "climate.sample_thermostat",
        humiditySensors: ["sensor.sample_hall_humidity", "sensor.sample_bedroom_humidity"],
        lock: "lock.sample_front_door",
        lights: ["light.sample_kitchen", "light.sample_living_room", "light.sample_hall"],
        people: ["person.sample_alex", "person.sample_sam"],
        bedroomTV: "media_player.sample_bedroom_tv",
        scenes: ["scene.sample_goodnight", "scene.sample_movie", "script.sample_morning"]
    )

    /// States for the selected entities that raise `kind`. `base` supplies the entities' real
    /// attributes when running against a live selection; the fixtures fill in otherwise.
    static func overrides(
        raising kind: HomeNudgeKind,
        selection: HomeSelection,
        base: [String: HAEntity] = [:]
    ) -> [String: HAEntity] {
        let sample = Dictionary(uniqueKeysWithValues: entities.map { ($0.entityID, $0) })
        func entity(_ id: String, state: String) -> HAEntity {
            var entity = base[id] ?? sample[id] ?? HAEntity(entityID: id, state: state)
            entity.state = state
            return entity
        }
        func only(_ ids: [String], state: String) -> [String: HAEntity] {
            Dictionary(uniqueKeysWithValues: ids.map { ($0, entity($0, state: state)) })
        }
        switch kind {
        case .dryAir:
            return only(selection.humiditySensors.prefix(1).map { $0 }, state: "31")
        case .humidAir:
            return only(selection.humiditySensors.prefix(1).map { $0 }, state: "66")
        case .doorUnlockedLate:
            return only(selection.lock.map { [$0] } ?? [], state: "unlocked")
        case .lightsOnAway:
            var result = only(selection.lights.prefix(1).map { $0 }, state: "on")
            result.merge(only(selection.people, state: "not_home")) { $1 }
            return result
        case .bedroomTVLate:
            return only(selection.bedroomTV.map { [$0] } ?? [], state: "on")
        }
    }

    private static func humidity(_ id: String, _ name: String, _ percent: Int) -> HAEntity {
        HAEntity(entityID: id, state: "\(percent)", attributes: [
            "friendly_name": .string(name),
            "device_class": .string("humidity"),
            "unit_of_measurement": .string("%"),
        ])
    }

    private static func light(_ id: String, _ name: String, on: Bool) -> HAEntity {
        HAEntity(entityID: id, state: on ? "on" : "off", attributes: ["friendly_name": .string(name)])
    }

    private static func person(_ id: String, _ name: String, home: Bool) -> HAEntity {
        HAEntity(entityID: id, state: home ? "home" : "not_home", attributes: ["friendly_name": .string(name)])
    }
}
#endif
