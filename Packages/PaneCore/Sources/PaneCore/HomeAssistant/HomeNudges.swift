import Foundation

public enum HomeNudgeKind: String, CaseIterable, Sendable, Codable {
    case dryAir
    case humidAir
    case doorUnlockedLate
    case lightsOnAway
    case bedroomTVLate

    /// The chip text on the Home card.
    public var chipText: String {
        switch self {
        case .dryAir: "Dry air"
        case .humidAir: "Humid air"
        case .doorUnlockedLate: "Unlocked late"
        case .lightsOnAway: "Nobody home"
        case .bedroomTVLate: "Bedroom TV on"
        }
    }

    /// The Settings toggle title.
    public var settingsTitle: String {
        switch self {
        case .dryAir: "Dry air below 35%"
        case .humidAir: "Humid air above 60%"
        case .doorUnlockedLate: "Door unlocked after 10 PM"
        case .lightsOnAway: "Lights on with nobody home"
        case .bedroomTVLate: "Bedroom TV on after midnight"
        }
    }
}

/// Which nudges the owner turned off in Settings. All are on by default.
public struct HomeNudgePreferences: Hashable, Sendable, Codable {
    public var disabled: Set<HomeNudgeKind>

    public init(disabled: Set<HomeNudgeKind> = []) {
        self.disabled = disabled
    }

    public func isEnabled(_ kind: HomeNudgeKind) -> Bool {
        !disabled.contains(kind)
    }

    public mutating func setEnabled(_ enabled: Bool, _ kind: HomeNudgeKind) {
        if enabled { disabled.remove(kind) } else { disabled.insert(kind) }
    }
}

public struct HomeNudge: Hashable, Sendable, Identifiable {
    public let kind: HomeNudgeKind
    /// The entities that raised it, for the card to place the chip on the right row.
    public let entityIDs: [String]

    public init(kind: HomeNudgeKind, entityIDs: [String] = []) {
        self.kind = kind
        self.entityIDs = entityIDs
    }

    public var id: HomeNudgeKind { kind }
}
