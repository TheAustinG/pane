import Foundation

/// What the Home card shows, built from the selected entities' current states.
public struct HomeSummary: Hashable, Sendable {
    public struct Climate: Hashable, Sendable {
        public var name: String
        public var insideTemperature: Double?
        /// `heating`, `cooling`, `idle`, `off` and so on, as Home Assistant reports `hvac_action`.
        public var action: String?
        /// The thermostat's mode (`heat`, `cool`, `heat_cool`, `off`).
        public var mode: String
        public var targetTemperature: Double?
        public var targetLow: Double?
        public var targetHigh: Double?
        public var isUnavailable: Bool
    }

    public struct Reading: Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// nil while the sensor is unavailable.
        public var percent: Double?
    }

    public struct Lock: Hashable, Sendable {
        public var name: String
        /// `locked`, `unlocked`, `jammed`, `locking`, `unlocking`, `open`, `unavailable`.
        public var state: String
        public var since: Date?
    }

    public struct Light: Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var isOn: Bool
    }

    public struct Person: Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var isHome: Bool
    }

    public var climate: Climate?
    public var humidity: [Reading]
    public var lock: Lock?
    public var lights: [Light]
    public var people: [Person]
    public var nudges: [HomeNudge]

    public init(
        climate: Climate? = nil,
        humidity: [Reading] = [],
        lock: Lock? = nil,
        lights: [Light] = [],
        people: [Person] = [],
        nudges: [HomeNudge] = []
    ) {
        self.climate = climate
        self.humidity = humidity
        self.lock = lock
        self.lights = lights
        self.people = people
        self.nudges = nudges
    }

    public var lightsOn: [Light] { lights.filter(\.isOn) }

    public func nudge(_ kind: HomeNudgeKind) -> HomeNudge? {
        nudges.first { $0.kind == kind }
    }

    /// Selected entities missing from `entities` are left out, so a renamed entity never shows a
    /// blank row.
    public static func make(
        entities: [String: HAEntity],
        selection: HomeSelection,
        nudges: [HomeNudge]
    ) -> HomeSummary {
        var summary = HomeSummary(nudges: nudges)
        if let id = selection.thermostat, let entity = entities[id] {
            let attributes = entity.attributes
            summary.climate = Climate(
                name: entity.friendlyName,
                insideTemperature: attributes["current_temperature"]?.number,
                action: attributes["hvac_action"]?.string,
                mode: entity.state,
                targetTemperature: attributes["temperature"]?.number,
                targetLow: attributes["target_temp_low"]?.number,
                targetHigh: attributes["target_temp_high"]?.number,
                isUnavailable: entity.isUnavailable
            )
        }
        summary.humidity = selection.humiditySensors.compactMap { id in
            entities[id].map { Reading(id: id, name: $0.friendlyName, percent: $0.numericState) }
        }
        if let id = selection.lock, let entity = entities[id] {
            summary.lock = Lock(name: entity.friendlyName, state: entity.state, since: entity.lastChanged)
        }
        summary.lights = selection.lights.compactMap { id in
            entities[id].map { Light(id: id, name: $0.friendlyName, isOn: $0.state == "on") }
        }
        summary.people = selection.people.compactMap { id in
            entities[id].map { Person(id: id, name: $0.friendlyName, isHome: $0.state == "home") }
        }
        return summary
    }
}
