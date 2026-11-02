import Foundation
@testable import PaneCore

enum NightTestClock {
    static let chicago: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    /// Local wall-clock time in Chicago. Only for times that exist exactly once.
    static func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        chicago.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// An exact instant from an ISO 8601 string with an offset, for the repeated hour.
    static func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}

extension NightSchedule {
    static func window(_ startHour: Int, _ startMinute: Int = 0, to endHour: Int, _ endMinute: Int = 0) -> NightSchedule {
        NightSchedule(
            isEnabled: true,
            start: ClockTime(hour: startHour, minute: startMinute),
            end: ClockTime(hour: endHour, minute: endMinute)
        )
    }
}
