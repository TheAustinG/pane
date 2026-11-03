import Foundation

/// The one-line note under the current conditions. The first rule that applies wins: wet now,
/// fog now, precipitation ahead, the coming high or low, then a steady sky.
struct WeatherNoteRules {
    let report: WeatherReport
    let date: Date
    let calendar: Calendar
    let format: TemperatureFormat
    let sun: SunTimes

    static let nearHours = 6
    static let aheadHours = 12
    static let likelyChance = 0.5
    static let possibleChance = 0.3

    func note() -> WeatherDisplay.Note? {
        let now = report.conditions(at: date)
        let family = ConditionFamily(weatherKitCondition: now.condition)
        let near = hours(within: Self.nearHours)
        if let kind = Precipitation(family) { return wetNow(kind, near: near) }
        if family == .fog { return fogNow(near: near) }
        if let note = precipitationAhead() { return note }
        let isDay = isDaytime(fallback: now.isDaylight)
        if let note = isDay ? comingHigh(from: now.temperature) : comingLow(from: now.temperature) {
            return note
        }
        return steadySky(family, near: near, isDay: isDay)
    }

    private func wetNow(_ kind: Precipitation, near: [HourForecast]) -> WeatherDisplay.Note? {
        guard let last = near.last else { return nil }
        if let dry = near.first(where: { !isWet($0) }) {
            return .init(text: "Tapering off around \(hourName(dry.date))", symbolName: kind.symbolName)
        }
        return .init(text: "\(kind.noun) through the \(period(of: last.date))", symbolName: kind.symbolName)
    }

    private func fogNow(near: [HourForecast]) -> WeatherDisplay.Note? {
        guard let last = near.last else { return nil }
        if let clear = near.first(where: { ConditionFamily(weatherKitCondition: $0.condition) != .fog }) {
            return .init(text: "Lifting by \(hourName(clear.date))", symbolName: "sun.haze")
        }
        return .init(text: "Fog through the \(period(of: last.date))", symbolName: "cloud.fog")
    }

    private func precipitationAhead() -> WeatherDisplay.Note? {
        let ahead = hours(within: Self.aheadHours)
        if let hour = ahead.first(where: { $0.precipitationChance >= Self.likelyChance }) {
            let kind = Precipitation(hour: hour)
            return .init(text: "\(kind.noun) likely after \(hourName(hour.date))", symbolName: kind.symbolName)
        }
        if let hour = ahead.first(where: { $0.precipitationChance >= Self.possibleChance }) {
            let kind = Precipitation(hour: hour)
            return .init(text: "Chance of \(kind.word) after \(hourName(hour.date))", symbolName: kind.symbolName)
        }
        return nil
    }

    private func comingHigh(from temperature: Double) -> WeatherDisplay.Note? {
        let sunset = sun.sunset(on: date)
        let window = sunset.map { end in report.hourly.filter { $0.date > date && $0.date < end } }
            ?? hours(within: Self.nearHours)
        guard let peak = window.max(by: { $0.temperature < $1.temperature }),
              format.value(peak.temperature) > format.value(temperature) else { return nil }
        // The day's high can fall between hourly samples; quoting it keeps the note in step with the
        // card's H, but only while no earlier hour today has already reached the coming peak.
        let earlier = report.hourly.filter { $0.date <= date && calendar.isDate($0.date, inSameDayAs: date) }
        let highIsAhead = earlier.allSatisfy { $0.temperature < peak.temperature }
        let dayHigh = report.day(containing: date, calendar: calendar)?.high ?? peak.temperature
        let high = highIsAhead ? max(peak.temperature, dayHigh) : peak.temperature
        return .init(text: "High of \(format.string(high)) around \(hourName(peak.date))", symbolName: "thermometer.high")
    }

    private func comingLow(from temperature: Double) -> WeatherDisplay.Note? {
        let sunrise = sun.nextSunrise(after: date)
        let window = sunrise.map { end in report.hourly.filter { $0.date > date && $0.date < end } }
            ?? hours(within: Self.aheadHours)
        guard let low = window.min(by: { $0.temperature < $1.temperature }),
              format.value(low.temperature) < format.value(temperature) else { return nil }
        let nearSunrise = sunrise.map { $0.timeIntervalSince(low.date) <= 2 * 3600 } ?? false
        let when = nearSunrise ? "just before sunrise" : "around \(hourName(low.date))"
        return .init(text: "Low of \(format.string(low.temperature)) \(when)", symbolName: "thermometer.low")
    }

    private func steadySky(_ family: ConditionFamily, near: [HourForecast], isDay: Bool) -> WeatherDisplay.Note? {
        guard let last = near.last,
              near.allSatisfy({ ConditionFamily(weatherKitCondition: $0.condition) == family }) else { return nil }
        let through = "through the \(period(of: last.date))"
        switch family {
        case .clear:
            return .init(text: "Clear skies \(through)", symbolName: isDay ? "sun.max" : "moon.stars")
        case .partlyCloudy:
            return .init(text: "Partly cloudy \(through)", symbolName: isDay ? "cloud.sun" : "cloud.moon")
        case .cloudy:
            return .init(text: "Cloudy \(through)", symbolName: "cloud")
        default:
            return nil
        }
    }

    /// Hours that start after the moment and within `count` hours of it.
    private func hours(within count: Int) -> [HourForecast] {
        let end = date.addingTimeInterval(TimeInterval(count) * 3600)
        return report.hourly.filter { $0.date > date && $0.date <= end }
    }

    private func isWet(_ hour: HourForecast) -> Bool {
        Precipitation(ConditionFamily(weatherKitCondition: hour.condition)) != nil
            || hour.precipitationChance >= Self.likelyChance
    }

    private func isDaytime(fallback: Bool) -> Bool {
        guard let sunrise = sun.sunrise(on: date), let sunset = sun.sunset(on: date) else { return fallback }
        return date >= sunrise && date < sunset
    }

    private func hourName(_ date: Date) -> String {
        HourLabel.string(date, calendar: calendar)
    }

    private func period(of date: Date) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        case 17..<21: "evening"
        default: "night"
        }
    }
}

private enum Precipitation {
    case rain, snow, storms

    init?(_ family: ConditionFamily) {
        switch family {
        case .rain: self = .rain
        case .snow: self = .snow
        case .storm: self = .storms
        case .clear, .partlyCloudy, .cloudy, .fog: return nil
        }
    }

    /// An hour with a high chance but a dry condition still names a kind: snow at or below freezing.
    init(hour: HourForecast) {
        self = Precipitation(ConditionFamily(weatherKitCondition: hour.condition))
            ?? (hour.temperature <= 0 ? .snow : .rain)
    }

    var noun: String {
        switch self {
        case .rain: "Rain"
        case .snow: "Snow"
        case .storms: "Storms"
        }
    }

    var word: String { noun.lowercased() }

    var symbolName: String {
        switch self {
        case .rain: "cloud.rain"
        case .snow: "cloud.snow"
        case .storms: "cloud.bolt.rain"
        }
    }
}
