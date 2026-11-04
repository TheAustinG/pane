import Foundation

/// When each Home nudge is raised. A rule is skipped when the owner turned it off, or when none of
/// its selected entities has a usable state.
public enum HomeNudgeRules {
    /// Dry air: the lowest selected humidity reading is below this percentage.
    public static let dryAirBelow: Double = 35
    /// A raised dry air nudge holds until every reading is at or above this, so a sensor hovering
    /// at `dryAirBelow` does not flap.
    public static let dryAirClearsAt: Double = 37
    /// Humid air: the highest selected humidity reading is above this percentage.
    public static let humidAirAbove: Double = 60
    /// A raised humid air nudge holds until every reading is at or below this.
    public static let humidAirClearsAt: Double = 58
    /// Door unlocked late: local hours from 22:00 up to, not including, 06:00.
    public static let doorLateHours = HourWindow(from: 22, until: 6)
    /// Lock states that do not raise the door nudge; every other usable state does, including
    /// `unlocked`, `unlocking`, `open`, `opening` and `jammed`.
    public static let lockSecureStates: Set<String> = ["locked", "locking"]
    /// Bedroom TV on late: local hours from 00:00 up to, not including, 05:00.
    public static let tvLateHours = HourWindow(from: 0, until: 5)
    /// Media player states that count as off.
    public static let tvOffStates: Set<String> = ["off", "standby", "unavailable", "unknown"]

    /// Raised nudges in `HomeNudgeKind.allCases` order. `previous` is the last result, which the
    /// humidity rules use to hold a raised nudge.
    public static func evaluate(
        entities: [String: HAEntity],
        selection: HomeSelection,
        preferences: HomeNudgePreferences,
        previous: [HomeNudge],
        at date: Date,
        calendar: Calendar
    ) -> [HomeNudge] {
        let raised = Set(previous.map(\.kind))
        let hour = calendar.component(.hour, from: date)
        return HomeNudgeKind.allCases.compactMap { kind in
            guard preferences.isEnabled(kind) else { return nil }
            let ids: [String]
            switch kind {
            case .dryAir:
                let threshold = raised.contains(.dryAir) ? dryAirClearsAt : dryAirBelow
                ids = humidity(in: entities, selection: selection).filter { $0.percent < threshold }.map(\.id)
            case .humidAir:
                let threshold = raised.contains(.humidAir) ? humidAirClearsAt : humidAirAbove
                ids = humidity(in: entities, selection: selection).filter { $0.percent > threshold }.map(\.id)
            case .doorUnlockedLate:
                ids = doorLateHours.contains(hour: hour) ? unlockedLock(in: entities, selection: selection) : []
            case .lightsOnAway:
                ids = lightsOnWithNobodyHome(in: entities, selection: selection)
            case .bedroomTVLate:
                ids = tvLateHours.contains(hour: hour) ? tvOn(in: entities, selection: selection) : []
            }
            return ids.isEmpty ? nil : HomeNudge(kind: kind, entityIDs: ids)
        }
    }

    private static func usable(_ id: String, in entities: [String: HAEntity]) -> HAEntity? {
        guard let entity = entities[id], !entity.isUnavailable else { return nil }
        return entity
    }

    private static func humidity(in entities: [String: HAEntity], selection: HomeSelection) -> [(id: String, percent: Double)] {
        selection.humiditySensors.compactMap { id in
            usable(id, in: entities)?.numericState.map { (id, $0) }
        }
    }

    private static func unlockedLock(in entities: [String: HAEntity], selection: HomeSelection) -> [String] {
        guard let id = selection.lock, let lock = usable(id, in: entities), !lockSecureStates.contains(lock.state) else { return [] }
        return [id]
    }

    /// Names the lights that are on: the card places the chip on the lights row.
    private static func lightsOnWithNobodyHome(in entities: [String: HAEntity], selection: HomeSelection) -> [String] {
        let people = selection.people.compactMap { usable($0, in: entities) }
        guard !people.isEmpty, !people.contains(where: { $0.state == "home" }) else { return [] }
        return selection.lights.filter { usable($0, in: entities)?.state == "on" }
    }

    private static func tvOn(in entities: [String: HAEntity], selection: HomeSelection) -> [String] {
        guard let id = selection.bedroomTV, let tv = usable(id, in: entities), !tvOffStates.contains(tv.state) else { return [] }
        return [id]
    }
}

/// Whole local hours from `from` up to, not including, `until`, wrapping past midnight when
/// `until` is earlier.
public struct HourWindow: Hashable, Sendable {
    public let from: Int
    public let until: Int

    public init(from: Int, until: Int) {
        self.from = from
        self.until = until
    }

    public func contains(hour: Int) -> Bool {
        from <= until ? (from..<until).contains(hour) : hour >= from || hour < until
    }
}
