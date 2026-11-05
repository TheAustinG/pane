import Foundation

extension CalendarDay {
    /// GitHub names days in the Gregorian calendar whatever the device's calendar is, and a day has
    /// no time zone, so stepping happens at noon UTC where no clock change can land.
    static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.init(date: date, calendar: calendar)
    }

    private var noonUTC: Date? {
        Self.gregorianUTC.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    public func adding(days: Int) -> CalendarDay {
        guard let noon = noonUTC, let moved = Self.gregorianUTC.date(byAdding: .day, value: days, to: noon) else { return self }
        return CalendarDay(date: moved, calendar: Self.gregorianUTC)
    }

    /// 1 for Sunday through 7 for Saturday.
    public var weekday: Int {
        noonUTC.map { Self.gregorianUTC.component(.weekday, from: $0) } ?? 1
    }
}

extension ContributionSummary {
    /// The summary for `weeks` columns ending at the week holding `today`, Sunday to Saturday in each
    /// column. Days after today are -1 and days the calendar lacks are 0.
    public static func make(calendar: ContributionCalendar, today: CalendarDay, weeks: Int) -> ContributionSummary {
        let byDay = Dictionary(calendar.days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        let count: (CalendarDay) -> Int = { byDay[$0]?.count ?? 0 }

        let todayCount = count(today)
        var streak = 0
        var day = todayCount > 0 ? today : today.adding(days: -1)
        while count(day) > 0 {
            streak += 1
            day = day.adding(days: -1)
        }

        let columns = max(weeks, 0)
        var levels: [Int] = []
        levels.reserveCapacity(columns * 7)
        if columns > 0 {
            let lastSunday = today.adding(days: -(today.weekday - 1))
            var cell = lastSunday.adding(days: -7 * (columns - 1))
            for _ in 0..<(columns * 7) {
                levels.append(cell > today ? -1 : min(max(byDay[cell]?.level ?? 0, 0), 4))
                cell = cell.adding(days: 1)
            }
        }
        return ContributionSummary(streak: streak, todayCount: todayCount, levels: levels)
    }
}
