#if DEBUG
import Foundation
import PaneCore

/// Sample weather for `-fixtures sample`, matching the design preview's scene samples.
enum WeatherFixtures {
    static func service(scene: String?, fixedNow: Date?) -> any WeatherService {
        FixtureWeatherService(preset: ScenePreset.named(scene) ?? .golden, fixedNow: fixedNow)
    }
}

struct FixtureWeatherService: WeatherService {
    let preset: ScenePreset
    let fixedNow: Date?

    var callsPerReport: Int { 0 }

    func report(for location: GeoPoint) async throws -> WeatherReport {
        let now = fixedNow ?? .now
        return WeatherReport(
            fetchedAt: now,
            location: location,
            current: CurrentConditions(
                date: now,
                temperature: 11,
                apparentTemperature: 11,
                humidity: 0.6,
                condition: "partlyCloudy",
                symbolName: preset.symbol,
                isDaylight: true
            ),
            hourly: [],
            daily: [],
            minutes: nil,
            alerts: nil
        )
    }

    func attribution() async throws -> WeatherAttributionInfo {
        throw URLError(.notConnectedToInternet)
    }
}
#endif
