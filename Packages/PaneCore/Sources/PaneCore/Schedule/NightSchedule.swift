import Foundation

public struct ClockTime: Hashable, Sendable, Codable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
}

public struct NightSchedule: Hashable, Sendable, Codable {
    public var isEnabled: Bool
    public var start: ClockTime
    public var end: ClockTime

    public init(isEnabled: Bool, start: ClockTime, end: ClockTime) {
        self.isEnabled = isEnabled
        self.start = start
        self.end = end
    }

    public static let standard = NightSchedule(
        isEnabled: true,
        start: ClockTime(hour: 23, minute: 0),
        end: ClockTime(hour: 6, minute: 30)
    )

    public func isActive(at date: Date, calendar: Calendar) -> Bool {
        false
    }

    /// The next time the schedule turns on or off after `date`, or nil when it is disabled.
    public func nextChange(after date: Date, calendar: Calendar) -> Date? {
        nil
    }
}

/// A manual choice that beats the schedule until it expires.
public enum NightDimOverride: Hashable, Sendable, Codable {
    case none
    case dimmed(until: Date)
    case bright(until: Date)
}

public enum NightDim {
    public static func isDimmed(
        at date: Date,
        schedule: NightSchedule,
        override: NightDimOverride,
        calendar: Calendar
    ) -> Bool {
        false
    }

    /// The override "Dim now" or "Brighten now" sets: it holds until the schedule next changes.
    public static func toggled(
        at date: Date,
        schedule: NightSchedule,
        current: NightDimOverride,
        calendar: Calendar
    ) -> NightDimOverride {
        .none
    }
}
