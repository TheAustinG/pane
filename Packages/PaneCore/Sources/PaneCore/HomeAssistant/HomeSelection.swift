import Foundation

/// Which entities the Home card shows, chosen in Settings.
public struct HomeSelection: Hashable, Sendable, Codable {
    public var thermostat: String?
    public var humiditySensors: [String]
    public var lock: String?
    public var lights: [String]
    public var people: [String]
    public var bedroomTV: String?
    /// Scene buttons, in display order.
    public var scenes: [String]
    /// The scene button that also starts night dim; nil picks a scene named Goodnight.
    public var goodnightScene: String?

    public init(
        thermostat: String? = nil,
        humiditySensors: [String] = [],
        lock: String? = nil,
        lights: [String] = [],
        people: [String] = [],
        bedroomTV: String? = nil,
        scenes: [String] = [],
        goodnightScene: String? = nil
    ) {
        self.thermostat = thermostat
        self.humiditySensors = humiditySensors
        self.lock = lock
        self.lights = lights
        self.people = people
        self.bedroomTV = bedroomTV
        self.scenes = scenes
        self.goodnightScene = goodnightScene
    }

    public static let empty = HomeSelection()

    public var isEmpty: Bool { self == .empty }

    public func entityIDs(for role: HomeEntityRole) -> [String] {
        switch role {
        case .thermostat: thermostat.map { [$0] } ?? []
        case .humidity: humiditySensors
        case .lock: lock.map { [$0] } ?? []
        case .lights: lights
        case .people: people
        case .bedroomTV: bedroomTV.map { [$0] } ?? []
        case .scenes: scenes
        }
    }

    public mutating func setEntityIDs(_ ids: [String], for role: HomeEntityRole) {
        switch role {
        case .thermostat: thermostat = ids.first
        case .humidity: humiditySensors = ids
        case .lock: lock = ids.first
        case .lights: lights = ids
        case .people: people = ids
        case .bedroomTV: bedroomTV = ids.first
        case .scenes:
            scenes = ids
            if let goodnightScene, !ids.contains(goodnightScene) { self.goodnightScene = nil }
        }
    }

    /// The scene button that starts night dim: the chosen one, else the first selected scene whose
    /// name or id says Goodnight.
    public func goodnightEntityID(in entities: [String: HAEntity]) -> String? {
        if let goodnightScene, scenes.contains(goodnightScene) { return goodnightScene }
        return scenes.first { id in
            let name = (entities[id]?.friendlyName ?? id).lowercased()
            return [name, id.lowercased()].contains { $0.contains("goodnight") || $0.contains("good night") || $0.contains("good_night") }
        }
    }
}

/// A slot in the entity picker.
public enum HomeEntityRole: String, CaseIterable, Sendable, Codable {
    case thermostat
    case humidity
    case lock
    case lights
    case people
    case bedroomTV
    case scenes

    public var title: String {
        switch self {
        case .thermostat: "Thermostat"
        case .humidity: "Humidity sensors"
        case .lock: "Door lock"
        case .lights: "Lights"
        case .people: "People"
        case .bedroomTV: "Bedroom TV"
        case .scenes: "Scene buttons"
        }
    }

    public var allowsMany: Bool {
        switch self {
        case .humidity, .lights, .people, .scenes: true
        case .thermostat, .lock, .bedroomTV: false
        }
    }

    public var domains: Set<String> {
        switch self {
        case .thermostat: ["climate"]
        case .humidity: ["sensor"]
        case .lock: ["lock"]
        case .lights: ["light", "switch", "input_boolean"]
        case .people: ["person", "device_tracker"]
        case .bedroomTV: ["media_player"]
        case .scenes: ["scene", "script", "input_button"]
        }
    }

    /// Entities this role can pick, sorted by name.
    public func candidates(in entities: some Sequence<HAEntity>) -> [HAEntity] {
        entities
            .filter { domains.contains($0.domain) && (self != .humidity || $0.deviceClass == "humidity") }
            .sorted { $0.friendlyName.localizedStandardCompare($1.friendlyName) == .orderedAscending }
    }
}
