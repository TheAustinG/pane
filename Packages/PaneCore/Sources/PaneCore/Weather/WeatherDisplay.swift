import Foundation

/// Everything the weather cards show, worked out from a report at one moment. Built fresh each
/// minute by the cards, so `-now` and the debug time scrub replay the report's own hours.
public struct WeatherDisplay: Hashable, Sendable {
    public struct Now: Hashable, Sendable {
        public var temperature: String
        public var condition: String
        public var symbolName: String
        public var family: ConditionFamily
        public var high: String
        public var low: String
    }

    public struct Hour: Hashable, Sendable {
        /// "Now", then "5 PM".
        public var label: String
        public var symbolName: String
        public var temperature: String
        /// Rounded to 10s; nil below 20 percent.
        public var precipitationPercent: Int?
    }

    public struct Day: Hashable, Sendable {
        /// "Today" is not used; the mockup shows weekday names ("Mon").
        public var label: String
        public var symbolName: String
        public var high: String
        public var low: String
    }

    public struct Daylight: Hashable, Sendable {
        /// 0 at sunrise, 1 at sunset, nil outside daylight.
        public var fraction: Double?
        public var sunrise: String
        public var sunset: String
        /// "Sunset in 33 min", "5h 15m of light left", "Sunrise in 19 min", "Sunrise 6:23 AM" or "Night".
        public var caption: String
    }

    public struct Note: Hashable, Sendable {
        /// "Rain likely after 9 PM", "Tapering off around 6 PM", "Clear skies through the evening".
        public var text: String
        public var symbolName: String
    }

    public var now: Now
    /// Six entries: now and the next five hours.
    public var hours: [Hour]
    /// Five entries starting today.
    public var days: [Day]
    public var daylight: Daylight
    public var note: Note?

    public init(
        report: WeatherReport,
        at date: Date,
        calendar: Calendar = .current,
        unit: UnitTemperature = .preferred
    ) {
        let conditions = report.conditions(at: date)
        let format = TemperatureFormat(unit: unit)
        let today = report.day(containing: date, calendar: calendar)
        let sun = SunTimes(report: report, calendar: calendar)
        now = Now(
            temperature: format.string(conditions.temperature),
            condition: WeatherConditionText.title(for: conditions.condition, isDaylight: conditions.isDaylight),
            symbolName: conditions.symbolName,
            family: ConditionFamily(weatherKitCondition: conditions.condition),
            high: today.map { format.string($0.high) } ?? "--",
            low: today.map { format.string($0.low) } ?? "--"
        )
        hours = report.hours(startingAt: date, count: 6).enumerated().map { index, hour in
            Hour(
                label: index == 0 ? "Now" : HourLabel.string(hour.date, calendar: calendar),
                symbolName: hour.symbolName,
                temperature: format.string(hour.temperature),
                precipitationPercent: Self.percent(hour.precipitationChance)
            )
        }
        days = report.days(startingAt: date, count: 5, calendar: calendar).map { day in
            Day(
                label: calendar.shortWeekdaySymbols[calendar.component(.weekday, from: day.date) - 1],
                symbolName: day.symbolName,
                high: format.string(day.high),
                low: format.string(day.low)
            )
        }
        daylight = Self.makeDaylight(
            sunrise: sun.sunrise(on: date),
            sunset: sun.sunset(on: date),
            at: date,
            calendar: calendar
        )
        note = WeatherNoteRules(report: report, date: date, calendar: calendar, format: format, sun: sun).note()
    }

    static func percent(_ chance: Double) -> Int? {
        guard chance >= 0.2 else { return nil }
        return Int((chance * 10).rounded()) * 10
    }

    static func makeDaylight(sunrise: Date?, sunset: Date?, at date: Date, calendar: Calendar) -> Daylight {
        let label = { (time: Date?) in time.map { ClockLabel.string($0, calendar: calendar) } ?? "--" }
        var fraction: Double?
        var caption = "Night"
        if let sunrise, let sunset, sunset > sunrise {
            if date < sunrise {
                let wait = sunrise.timeIntervalSince(date)
                caption = wait < 2 * 3600 ? "Sunrise in \(DurationText.string(wait))" : "Sunrise \(label(sunrise))"
            } else if date < sunset {
                fraction = date.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
                let left = sunset.timeIntervalSince(date)
                caption = left < 3600 ? "Sunset in \(DurationText.string(left))" : "\(DurationText.string(left)) of light left"
            }
        }
        return Daylight(fraction: fraction, sunrise: label(sunrise), sunset: label(sunset), caption: caption)
    }
}

/// The conditions at a moment: the current observation near fetch time, otherwise the hourly
/// entry that contains the moment.
public struct ConditionsAtTime: Hashable, Sendable {
    public var temperature: Double
    public var condition: String
    public var symbolName: String
    public var isDaylight: Bool
}

extension WeatherReport {
    /// How far from the observation the current conditions still stand in for the moment.
    static let currentWindow: TimeInterval = 45 * 60

    public func conditions(at date: Date) -> ConditionsAtTime {
        if abs(date.timeIntervalSince(current.date)) < Self.currentWindow || hourly.isEmpty {
            return ConditionsAtTime(
                temperature: current.temperature,
                condition: current.condition,
                symbolName: current.symbolName,
                isDaylight: current.isDaylight
            )
        }
        let hour = hourly.last(where: { $0.date <= date }) ?? hourly[0]
        return ConditionsAtTime(
            temperature: hour.temperature,
            condition: hour.condition,
            symbolName: hour.symbolName,
            isDaylight: hour.isDaylight
        )
    }

    public func hours(startingAt date: Date, count: Int) -> [HourForecast] {
        let first = hourly.lastIndex(where: { $0.date <= date }) ?? 0
        return Array(hourly[first...].prefix(count))
    }

    public func day(containing date: Date, calendar: Calendar) -> DayForecast? {
        daily.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    public func days(startingAt date: Date, count: Int, calendar: Calendar) -> [DayForecast] {
        let start = calendar.startOfDay(for: date)
        return Array(daily.filter { $0.date >= start }.prefix(count))
    }
}

/// Sunrise and sunset from the report's days, or from the sun math where a day has none.
struct SunTimes {
    let report: WeatherReport
    let calendar: Calendar

    func sunrise(on date: Date) -> Date? {
        report.day(containing: date, calendar: calendar)?.sunrise
            ?? SolarPosition.sunrise(on: date, location: report.location, timeZone: calendar.timeZone)
    }

    func sunset(on date: Date) -> Date? {
        report.day(containing: date, calendar: calendar)?.sunset
            ?? SolarPosition.sunset(on: date, location: report.location, timeZone: calendar.timeZone)
    }

    func nextSunrise(after date: Date) -> Date? {
        if let today = sunrise(on: date), today > date { return today }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
        return sunrise(on: tomorrow)
    }
}

struct TemperatureFormat {
    let unit: UnitTemperature

    func value(_ celsius: Double) -> Int {
        Int(Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit).value.rounded())
    }

    func string(_ celsius: Double) -> String {
        "\(value(celsius))°"
    }
}

extension UnitTemperature {
    /// Fahrenheit where the locale uses US measurements, Celsius elsewhere.
    public static var preferred: UnitTemperature {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

enum HourLabel {
    static func string(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(hour12) \(hour < 12 ? "AM" : "PM")"
    }
}

enum ClockLabel {
    static func string(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(hour12):\(String(format: "%02d", parts.minute ?? 0)) \(hour < 12 ? "AM" : "PM")"
    }
}

/// "33 min", "1h 40m", "5h" from a positive interval, counting whole minutes down.
enum DurationText {
    static func string(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval / 60), 1)
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest)m"
    }
}
