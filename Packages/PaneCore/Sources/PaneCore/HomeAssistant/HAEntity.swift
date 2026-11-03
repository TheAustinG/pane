import Foundation

/// A JSON value from Home Assistant: entity attributes and service data are free-form.
public enum HAValue: Hashable, Sendable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([HAValue])
    case object([String: HAValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([HAValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: HAValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Numbers, and strings that parse as numbers (sensor states arrive as strings).
    public var number: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var array: [HAValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> HAValue? {
        if case .object(let value) = self { return value[key] }
        return nil
    }
}

/// One entity's state as Home Assistant reports it in `get_states` and `state_changed`.
public struct HAEntity: Hashable, Sendable, Codable, Identifiable {
    public let entityID: String
    public var state: String
    public var attributes: [String: HAValue]
    public var lastChanged: Date?
    public var lastUpdated: Date?

    public init(
        entityID: String,
        state: String,
        attributes: [String: HAValue] = [:],
        lastChanged: Date? = nil,
        lastUpdated: Date? = nil
    ) {
        self.entityID = entityID
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated
    }

    public var id: String { entityID }

    public var domain: String {
        String(entityID.prefix { $0 != "." })
    }

    public var friendlyName: String {
        attributes["friendly_name"]?.string ?? entityID
    }

    public var deviceClass: String? {
        attributes["device_class"]?.string
    }

    public var unit: String? {
        attributes["unit_of_measurement"]?.string
    }

    public var numericState: Double? {
        Double(state)
    }

    public var isUnavailable: Bool {
        state == "unavailable" || state == "unknown"
    }
}
