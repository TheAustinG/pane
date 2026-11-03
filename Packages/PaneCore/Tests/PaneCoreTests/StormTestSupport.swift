import Foundation
import Synchronization
@testable import PaneCore

/// Reports with alerts, minute data and hourly chances for the storm rules.
enum StormFixture {
    static func alert(_ id: String, severity: String = "severe", summary: String? = nil, endDate: Date? = nil) -> WeatherAlertInfo {
        WeatherAlertInfo(
            id: id,
            summary: summary ?? "Alert \(id)",
            source: "National Weather Service",
            severity: severity,
            detailsURL: URL(string: "https://example.com/alerts/\(id)")!,
            region: nil,
            endDate: endDate
        )
    }

    /// An hour of minutes from `start`, wet (at `chance` and `intensity`) for the minute offsets in `wet`.
    static func minutes(from start: Date, wet: Range<Int>, chance: Double = 0.8, intensity: Double = 1.2) -> [MinuteForecast] {
        (0..<60).map { offset in
            let isWet = wet.contains(offset)
            return MinuteForecast(
                date: start.addingTimeInterval(TimeInterval(offset) * 60),
                precipitationChance: isWet ? chance : 0,
                precipitationIntensity: isWet ? intensity : 0
            )
        }
    }

    /// A report fetched at `fetchedAt` (default `now`), with `chance` for the hours `chanceAt` picks.
    static func report(
        at now: Date,
        fetchedAt: Date? = nil,
        alerts: [WeatherAlertInfo] = [],
        minutes: [MinuteForecast]? = nil,
        chance: Double = 0,
        chanceAt: @escaping (Date) -> Bool = { _ in true }
    ) -> WeatherReport {
        var report = WeatherFixture.report(at: now, hour: { date in
            WeatherFixture.HourSpec(chance: chanceAt(date) ? chance : 0)
        })
        report.fetchedAt = fetchedAt ?? now
        report.alerts = alerts
        report.minutes = minutes
        return report
    }
}

/// Hands back whatever report the test set last.
final class StormWeatherService: WeatherService {
    private let next = Mutex<WeatherReport?>(nil)
    let callsPerReport = 5

    func set(_ report: WeatherReport) {
        next.withLock { $0 = report }
    }

    func report(for location: GeoPoint) async throws -> WeatherReport {
        guard let report = next.withLock({ $0 }) else { throw URLError(.notConnectedToInternet) }
        return report
    }

    func attribution() async throws -> WeatherAttributionInfo {
        WeatherFixture.attribution
    }
}
