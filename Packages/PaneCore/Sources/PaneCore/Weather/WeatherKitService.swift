import CoreLocation
import Foundation
import WeatherKit

/// The live source: one WeatherKit request for current, hourly, daily, minute and alert data,
/// mapped into our own types.
public struct WeatherKitService: WeatherService {
    /// Seconds around the fetch time whose hours are kept. WeatherKit returns about 22 hours back
    /// and 227 ahead; the cards and `-now` replays need far less, and the cache stays small.
    public var hourlyWindow: ClosedRange<TimeInterval>

    public init(hourlyWindow: ClosedRange<TimeInterval> = -24 * 3600 ... 48 * 3600) {
        self.hourlyWindow = hourlyWindow
    }

    // Whether a request for several datasets bills as one call is unconfirmed, so the budget
    // counts one per dataset.
    public var callsPerReport: Int { 5 }

    public func report(for location: GeoPoint) async throws -> WeatherReport {
        let (current, hourly, daily, minute, alerts) = try await WeatherKit.WeatherService.shared.weather(
            for: CLLocation(latitude: location.latitude, longitude: location.longitude),
            including: .current, .hourly, .daily, .minute, .alerts
        )
        let fetchedAt = Date.now
        let window = fetchedAt.addingTimeInterval(hourlyWindow.lowerBound)...fetchedAt.addingTimeInterval(hourlyWindow.upperBound)
        return WeatherReport(
            fetchedAt: fetchedAt,
            location: location,
            current: CurrentConditions(current),
            hourly: hourly.forecast.filter { window.contains($0.date) }.map(HourForecast.init),
            daily: daily.forecast.map(DayForecast.init),
            minutes: minute?.forecast.map(MinuteForecast.init),
            alerts: alerts?.map(WeatherAlertInfo.init)
        )
    }

    public func attribution() async throws -> WeatherAttributionInfo {
        let attribution = try await WeatherKit.WeatherService.shared.attribution
        return WeatherAttributionInfo(
            serviceName: attribution.serviceName,
            legalPageURL: attribution.legalPageURL,
            combinedMarkDarkURL: attribution.combinedMarkDarkURL,
            combinedMarkLightURL: attribution.combinedMarkLightURL
        )
    }
}

private extension Measurement<UnitTemperature> {
    var celsius: Double { converted(to: .celsius).value }
}

private extension CurrentConditions {
    init(_ weather: CurrentWeather) {
        self.init(
            date: weather.date,
            temperature: weather.temperature.celsius,
            apparentTemperature: weather.apparentTemperature.celsius,
            humidity: weather.humidity,
            condition: weather.condition.rawValue,
            symbolName: weather.symbolName,
            isDaylight: weather.isDaylight
        )
    }
}

private extension HourForecast {
    init(_ hour: HourWeather) {
        self.init(
            date: hour.date,
            temperature: hour.temperature.celsius,
            condition: hour.condition.rawValue,
            symbolName: hour.symbolName,
            precipitationChance: hour.precipitationChance,
            isDaylight: hour.isDaylight
        )
    }
}

private extension DayForecast {
    init(_ day: DayWeather) {
        self.init(
            date: day.date,
            high: day.highTemperature.celsius,
            low: day.lowTemperature.celsius,
            condition: day.condition.rawValue,
            symbolName: day.symbolName,
            precipitationChance: day.precipitationChance,
            sunrise: day.sun.sunrise,
            sunset: day.sun.sunset
        )
    }
}

private extension MinuteForecast {
    init(_ minute: MinuteWeather) {
        self.init(
            date: minute.date,
            precipitationChance: minute.precipitationChance,
            precipitationIntensity: minute.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000
        )
    }
}

private extension WeatherAlertInfo {
    /// One `detailsURL` lists every alert active at the location, so it changes as alerts come and
    /// go and is shared between them; the id has to come from the alert itself.
    init(_ alert: WeatherAlert) {
        self.init(
            id: [alert.summary, alert.source, alert.region ?? ""].joined(separator: "|"),
            summary: alert.summary,
            source: alert.source,
            severity: alert.severity.rawValue,
            detailsURL: alert.detailsURL,
            region: alert.region
        )
    }
}
