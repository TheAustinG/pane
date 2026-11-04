import Foundation

/// One frame from Home Assistant's WebSocket API, decoded off the main actor.
enum HAInbound: Sendable {
    case authRequired(version: String?)
    case authOK(version: String?)
    case authInvalid(message: String?)
    case result(id: Int, Result<HAResultPayload?, HAErrorInfo>)
    /// `change` is nil for events other than `state_changed`.
    case event(id: Int, change: HAStateChange?)
    case pong(id: Int)
    case other(type: String)

    static func decode(_ text: String) -> HAInbound {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        guard let frame = try? decoder.decode(HAFrameWire.self, from: data) else {
            // A result we cannot read still has to answer its request, or the caller waits out the timeout.
            if let header = try? decoder.decode(HAHeaderWire.self, from: data), header.type == "result", let id = header.id {
                return .result(id: id, .failure(HAErrorInfo(code: "invalid_format", message: "Unreadable result")))
            }
            return .other(type: (try? decoder.decode(HAHeaderWire.self, from: data))?.type ?? "")
        }
        switch frame.type {
        case "auth_required": return .authRequired(version: frame.haVersion)
        case "auth_ok": return .authOK(version: frame.haVersion)
        case "auth_invalid": return .authInvalid(message: frame.message)
        case "result":
            guard let id = frame.id else { return .other(type: frame.type) }
            if frame.success == true { return .result(id: id, .success(frame.result)) }
            return .result(id: id, .failure(frame.error ?? HAErrorInfo(code: "unknown_error", message: "")))
        case "event":
            guard let id = frame.id else { return .other(type: frame.type) }
            return .event(id: id, change: frame.event.flatMap(HAStateChange.init(wire:)))
        case "pong":
            guard let id = frame.id else { return .other(type: frame.type) }
            return .pong(id: id)
        default:
            return .other(type: frame.type)
        }
    }
}

/// A `result` payload: `get_states` lists, decoded straight into entities, or anything else.
enum HAResultPayload: Sendable, Decodable {
    case states([HAEntity])
    case value(HAValue)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let states = try? container.decode([HAStateWire].self) {
            self = .states(states.map(\.entity))
        } else {
            self = .value(try container.decode(HAValue.self))
        }
    }
}

/// Home Assistant's `error` object on a failed `result`.
struct HAErrorInfo: Error, Hashable, Sendable, Decodable {
    let code: String
    let message: String
}

/// A `state_changed` event. `newState` is nil when the entity was removed.
struct HAStateChange: Sendable, Hashable {
    let entityID: String
    let newState: HAEntity?
    let timeFired: Date?

    init(entityID: String, newState: HAEntity?, timeFired: Date?) {
        self.entityID = entityID
        self.newState = newState
        self.timeFired = timeFired
    }

    init?(wire: HAEventWire) {
        guard wire.eventType == "state_changed", let entityID = wire.data?.entityID else { return nil }
        self.init(entityID: entityID, newState: wire.data?.newState?.entity, timeFired: wire.timeFired.flatMap(HADate.parse))
    }
}

/// Messages the client sends. Every command after `auth` carries an id that must increase.
enum HAOutbound {
    static func auth(token: String) -> String {
        encode(["type": .string("auth"), "access_token": .string(token)])
    }

    static func subscribeStateChanged(id: Int) -> String {
        encode(["id": .number(Double(id)), "type": .string("subscribe_events"), "event_type": .string("state_changed")])
    }

    static func getStates(id: Int) -> String {
        encode(["id": .number(Double(id)), "type": .string("get_states")])
    }

    static func callService(id: Int, domain: String, service: String, entityID: String) -> String {
        encode([
            "id": .number(Double(id)),
            "type": .string("call_service"),
            "domain": .string(domain),
            "service": .string(service),
            "target": .object(["entity_id": .string(entityID)]),
        ])
    }

    static func ping(id: Int) -> String {
        encode(["id": .number(Double(id)), "type": .string("ping")])
    }

    static func encode(_ object: [String: HAValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(HAValue.object(object)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Home Assistant timestamps: ISO 8601 with microseconds and an offset, such as
/// `2026-11-02T18:04:05.123456+00:00`.
enum HADate {
    static func parse(_ text: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return date }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    static func format(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let seconds = date.timeIntervalSince1970.rounded(.down)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: seconds))
        let micros = min(999_999, Int(((date.timeIntervalSince1970 - seconds) * 1_000_000).rounded()))
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%06d+00:00",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0, micros
        )
    }
}

extension HAEntity {
    /// The entity as Home Assistant serializes a state object.
    var wireValue: HAValue {
        var object: [String: HAValue] = [
            "entity_id": .string(entityID),
            "state": .string(state),
            "attributes": .object(attributes),
        ]
        if let lastChanged { object["last_changed"] = .string(HADate.format(lastChanged)) }
        if let lastUpdated { object["last_updated"] = .string(HADate.format(lastUpdated)) }
        return .object(object)
    }
}

struct HAStateWire: Decodable {
    let entityID: String
    let state: String
    let attributes: [String: HAValue]?
    let lastChanged: String?
    let lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }

    var entity: HAEntity {
        HAEntity(
            entityID: entityID,
            state: state,
            attributes: attributes ?? [:],
            lastChanged: lastChanged.flatMap(HADate.parse),
            lastUpdated: lastUpdated.flatMap(HADate.parse)
        )
    }
}

struct HAEventWire: Decodable {
    struct Payload: Decodable {
        let entityID: String?
        let newState: HAStateWire?

        enum CodingKeys: String, CodingKey {
            case entityID = "entity_id"
            case newState = "new_state"
        }
    }

    let eventType: String
    let data: Payload?
    let timeFired: String?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case data
        case timeFired = "time_fired"
    }
}

private struct HAHeaderWire: Decodable {
    let type: String
    let id: Int?
}

private struct HAFrameWire: Decodable {
    let type: String
    let id: Int?
    let haVersion: String?
    let message: String?
    let success: Bool?
    let error: HAErrorInfo?
    let event: HAEventWire?
    let result: HAResultPayload?

    enum CodingKeys: String, CodingKey {
        case type, id, message, success, error, event, result
        case haVersion = "ha_version"
    }
}
