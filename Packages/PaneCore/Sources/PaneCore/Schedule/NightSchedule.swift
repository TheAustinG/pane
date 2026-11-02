import Foundation

public struct ClockTime: Hashable, Sendable, Codable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    var minuteOfDay: Int { hour * 60 + minute }
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

    /// True when `date` falls in a dim window. A window starts at `start` and ends at `end`, on the
    /// next day when `end` is not later than `start`. `start == end` is an empty schedule.
    public func isActive(at date: Date, calendar: Calendar) -> Bool {
        guard isEnabled, start != end else { return false }
        return [-1, 0].contains { offset in
            guard let window = window(startingOnDayOffset: offset, from: date, calendar: calendar) else { return false }
            return window.start <= date && date < window.end
        }
    }

    /// The next time the schedule turns on or off after `date`, or nil when it never changes.
    public func nextChange(after date: Date, calendar: Calendar) -> Date? {
        guard isEnabled, start != end else { return nil }
        let candidates = (-1...2).flatMap { offset -> [Date] in
            guard let window = window(startingOnDayOffset: offset, from: date, calendar: calendar) else { return [] }
            return [window.start, window.end]
        }
        return candidates
            .filter { $0 > date }
            .sorted()
            .first { change in
                isActive(at: change, calendar: calendar) != isActive(at: change.addingTimeInterval(-0.5), calendar: calendar)
            }
    }

    /// The next time after `date` the schedule goes from on to off, or nil when it never does.
    public func nextEnd(after date: Date, calendar: Calendar) -> Date? {
        nextChange(after: date, calendar: calendar, turningOn: false)
    }

    /// The next time after `date` the schedule goes from off to on, or nil when it never does.
    public func nextStart(after date: Date, calendar: Calendar) -> Date? {
        nextChange(after: date, calendar: calendar, turningOn: true)
    }

    private func nextChange(after date: Date, calendar: Calendar, turningOn: Bool) -> Date? {
        var cursor = date
        for _ in 0..<4 {
            guard let change = nextChange(after: cursor, calendar: calendar) else { return nil }
            if isActive(at: change, calendar: calendar) == turningOn { return change }
            cursor = change
        }
        return nil
    }

    /// The next time of day `end` after `date`, used when the schedule itself is off.
    func nextEndTime(after date: Date, calendar: Calendar) -> Date? {
        (0...1).lazy
            .compactMap { Self.instant(of: end, dayOffset: $0, from: date, calendar: calendar) }
            .first { $0 > date }
    }

    private func window(startingOnDayOffset offset: Int, from date: Date, calendar: Calendar) -> (start: Date, end: Date)? {
        let endOffset = offset + (end.minuteOfDay > start.minuteOfDay ? 0 : 1)
        guard
            let windowStart = Self.instant(of: start, dayOffset: offset, from: date, calendar: calendar),
            let windowEnd = Self.instant(of: end, dayOffset: endOffset, from: date, calendar: calendar)
        else { return nil }
        return (windowStart, windowEnd)
    }

    /// A time that falls in a skipped hour moves to the first valid instant after it; one in a
    /// repeated hour takes the first occurrence.
    private static func instant(of time: ClockTime, dayOffset: Int, from date: Date, calendar: Calendar) -> Date? {
        guard
            let day = calendar.date(byAdding: .day, value: dayOffset, to: date)
        else { return nil }
        return calendar.date(
            bySettingHour: time.hour,
            minute: time.minute,
            second: 0,
            of: calendar.startOfDay(for: day),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
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
        switch override {
        case .dimmed(let until) where date < until: true
        case .bright(let until) where date < until: false
        default: schedule.isActive(at: date, calendar: calendar)
        }
    }

    /// The override "Dim now" or "Brighten now" sets.
    ///
    /// Dimmed to bright: holds until the current dim window ends, or when the schedule is not in a
    /// window, until the next one starts. Bright to dimmed: holds until the schedule next turns
    /// off. A disabled schedule has no windows, so either way the override holds until the next
    /// time of day `end` comes round.
    public static func toggled(
        at date: Date,
        schedule: NightSchedule,
        current: NightDimOverride,
        calendar: Calendar
    ) -> NightDimOverride {
        let dimmed = isDimmed(at: date, schedule: schedule, override: current, calendar: calendar)
        let fallback = schedule.nextEndTime(after: date, calendar: calendar)
            ?? date.addingTimeInterval(24 * 60 * 60)
        if dimmed {
            let until = schedule.isActive(at: date, calendar: calendar)
                ? schedule.nextEnd(after: date, calendar: calendar)
                : schedule.nextStart(after: date, calendar: calendar)
            return .bright(until: until ?? fallback)
        }
        return .dimmed(until: schedule.nextEnd(after: date, calendar: calendar) ?? fallback)
    }
}
