#if DEBUG
import Foundation
import PaneCore

/// Sample weather for `-fixtures sample`, matching the design preview's scene samples.
enum WeatherFixtures {
    static func service(scene: String?, fixedNow: Date?) -> any WeatherService {
        FixtureWeatherService(preset: ScenePreset.named(scene) ?? .golden, fixedNow: fixedNow)
    }

    /// The report `-fixtures sample` serves, for seeding the offline cache with the same data.
    @MainActor
    static func report(scene: String?, at date: Date) -> WeatherReport {
        FixtureWeatherService(preset: ScenePreset.named(scene) ?? .golden, fixedNow: date)
            .makeReport(for: AppModel.referenceLocation, at: date)
    }
}

struct FixtureWeatherService: WeatherService {
    let preset: ScenePreset
    let fixedNow: Date?

    var callsPerReport: Int { 0 }

    /// The sample is laid out around the pinned app time, but stamped as fetched just now.
    func report(for location: GeoPoint) async throws -> WeatherReport {
        var report = makeReport(for: location, at: fixedNow ?? .now)
        report.fetchedAt = .now
        return report
    }

    func attribution() async throws -> WeatherAttributionInfo {
        throw URLError(.notConnectedToInternet)
    }

    func makeReport(for location: GeoPoint, at now: Date) -> WeatherReport {
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let today = calendar.startOfDay(for: now)

        func daylight(at date: Date) -> Bool {
            SolarPosition.altitude(at: date, location: location) > 0
        }

        let sampleHours = preset.hourly
        let hourly = (-24..<48).map { offset -> HourForecast in
            let date = hourStart.addingTimeInterval(Double(offset) * 3600)
            let sample = sampleHours[min(max(offset, 0), sampleHours.count - 1)]
            let chance = offset >= 0 && offset < sampleHours.count ? Double(sample.pop ?? 0) / 100 : 0
            return HourForecast(
                date: date,
                temperature: Self.celsius(sample.temp),
                condition: Self.condition(for: sample.symbol),
                symbolName: sample.symbol,
                precipitationChance: chance,
                isDaylight: daylight(at: date)
            )
        }

        let daily = (0..<10).compactMap { offset -> DayForecast? in
            guard let start = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let sample = ScenePreset.daily[offset % ScenePreset.daily.count]
            return DayForecast(
                date: start,
                high: Self.celsius(offset == 0 ? preset.high : sample.high),
                low: Self.celsius(offset == 0 ? preset.low : sample.low),
                condition: Self.condition(for: sample.symbol),
                symbolName: sample.symbol,
                precipitationChance: sample.symbol.contains("rain") ? 0.6 : 0.1,
                sunrise: SolarPosition.sunrise(on: start, location: location, timeZone: calendar.timeZone),
                sunset: SolarPosition.sunset(on: start, location: location, timeZone: calendar.timeZone)
            )
        }

        return WeatherReport(
            fetchedAt: now,
            location: location,
            current: CurrentConditions(
                date: now,
                temperature: Self.celsius(preset.temp),
                apparentTemperature: Self.celsius(preset.temp),
                humidity: 0.6,
                condition: Self.condition(for: preset.symbol),
                symbolName: preset.symbol,
                isDaylight: daylight(at: now)
            ),
            hourly: hourly,
            daily: daily,
            minutes: nil,
            alerts: nil
        )
    }

    private static func celsius(_ fahrenheit: String) -> Double {
        let digits = fahrenheit.filter { $0.isNumber || $0 == "-" }
        return ((Double(digits) ?? 0) - 32) * 5 / 9
    }

    private static func condition(for symbol: String) -> String {
        switch symbol {
        case "cloud.sun", "cloud.moon": "partlyCloudy"
        case "cloud": "mostlyCloudy"
        case "cloud.drizzle": "drizzle"
        case "cloud.rain": "rain"
        case "cloud.snow": "snow"
        case "cloud.fog": "foggy"
        case "cloud.bolt.rain", "cloud.bolt": "thunderstorms"
        default: "clear"
        }
    }
}
#endif
