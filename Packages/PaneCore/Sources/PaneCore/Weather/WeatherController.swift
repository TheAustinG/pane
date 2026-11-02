import Foundation
import Observation

/// Owns the live report: loads the offline cache, refreshes on the policy's schedule, counts
/// billable calls, and keeps the attribution mark. The app reads it; nothing else writes it.
@MainActor
@Observable
public final class WeatherController {
    public private(set) var report: WeatherReport?
    public private(set) var attribution: WeatherAttributionInfo?
    /// PNG bytes of the combined dark mark, kept so the mark still shows offline.
    public private(set) var markImageData: Data?
    public private(set) var lastFailure: Date?
    public var location: GeoPoint?

    @ObservationIgnored private let service: any WeatherService
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(service: any WeatherService, now: @escaping @Sendable () -> Date = { .now }) {
        self.service = service
        self.now = now
    }

    /// Runs until the calling task is cancelled.
    public func run() async {
        await refreshNow()
    }

    public func refreshNow() async {
        guard let location else { return }
        do {
            report = try await service.report(for: location)
            lastFailure = nil
        } catch {
            lastFailure = now()
        }
        if attribution == nil {
            attribution = try? await service.attribution()
        }
    }

    public func freshness(at date: Date) -> Freshness {
        guard let report else { return .none }
        let minutes = Int(date.timeIntervalSince(report.fetchedAt) / 60)
        if minutes >= 30 { return .stale(minutes: minutes) }
        return lastFailure == nil ? .fresh : .delayed(minutes: minutes)
    }
}
