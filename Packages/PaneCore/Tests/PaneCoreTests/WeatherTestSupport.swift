import Foundation
import Synchronization
@testable import PaneCore

/// Hand-built reports for Chicago, the only place the tests use.
enum WeatherFixture {
    static let chicago = GeoPoint(latitude: 41.88, longitude: -87.63)
    static let grantPark = GeoPoint(latitude: 41.88, longitude: -87.62)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// Local wall-clock time in Chicago. Only for times that exist exactly once.
    static func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    struct HourSpec {
        var temperature: Double = 10
        var condition = "clear"
        var chance = 0.0
    }

    struct DaySpec {
        var high: Double = 15
        var low: Double = 5
        var condition = "clear"
        var chance = 0.0
        /// Nil uses the sun math; `.some(nil)` leaves the time out.
        var sunrise: Date?? = nil
        var sunset: Date?? = nil
    }

    /// A report fetched at `now`, with hours from a day before to two days after and days from
    /// yesterday to eight days ahead, the shape WeatherKit returns.
    static func report(
        at now: Date,
        location: GeoPoint = chicago,
        current: HourSpec? = nil,
        hour: (Date) -> HourSpec = { _ in HourSpec() },
        day: (Date) -> DaySpec = { _ in DaySpec() }
    ) -> WeatherReport {
        let firstHour = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        let hourly = (-24...48).map { offset in
            let date = firstHour.addingTimeInterval(TimeInterval(offset) * 3600)
            let spec = hour(date)
            return HourForecast(
                date: date,
                temperature: spec.temperature,
                condition: spec.condition,
                symbolName: symbol(for: spec.condition),
                precipitationChance: spec.chance,
                isDaylight: SolarPosition.altitude(at: date, location: location) > 0
            )
        }
        let today = calendar.startOfDay(for: now)
        let daily = (-1...8).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let spec = day(date)
            return DayForecast(
                date: date,
                high: spec.high,
                low: spec.low,
                condition: spec.condition,
                symbolName: symbol(for: spec.condition),
                precipitationChance: spec.chance,
                sunrise: spec.sunrise ?? wholeMinute(SolarPosition.sunrise(on: date, location: location, timeZone: calendar.timeZone)),
                sunset: spec.sunset ?? wholeMinute(SolarPosition.sunset(on: date, location: location, timeZone: calendar.timeZone))
            )
        }
        let currentSpec = current ?? hour(firstHour)
        return WeatherReport(
            fetchedAt: now,
            location: location,
            current: CurrentConditions(
                date: now,
                temperature: currentSpec.temperature,
                apparentTemperature: currentSpec.temperature,
                humidity: 0.6,
                condition: currentSpec.condition,
                symbolName: symbol(for: currentSpec.condition),
                isDaylight: SolarPosition.altitude(at: now, location: location) > 0
            ),
            hourly: hourly,
            daily: daily,
            minutes: nil,
            alerts: []
        )
    }

    static func symbol(for condition: String) -> String {
        "symbol.\(condition)"
    }

    /// The cache keeps dates to the whole second, so fixture sun times are whole minutes.
    private static func wholeMinute(_ date: Date?) -> Date? {
        date.map { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 / 60).rounded() * 60) }
    }

    static let attribution = WeatherAttributionInfo(
        serviceName: "Weather",
        legalPageURL: WeatherAttributionInfo.fallbackLegalPageURL,
        combinedMarkDarkURL: URL(string: "https://example.com/mark-dark.png")!,
        combinedMarkLightURL: URL(string: "https://example.com/mark-light.png")!
    )
}

/// A clock that only moves when the test says so. `sleep(until:)` suspends until `advance` passes
/// the deadline or the sleeping task is cancelled.
final class ManualClock: WeatherClock {
    private struct Sleeper {
        let id: Int
        let deadline: Date
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now: Date
        var nextID = 0
        var sleepers: [Sleeper] = []
        var cancelled: Set<Int> = []
        var idleWaiters: [CheckedContinuation<Date, Never>] = []
    }

    private let state: Mutex<State>

    init(now: Date) {
        state = Mutex(State(now: now))
    }

    var now: Date { state.withLock { $0.now } }

    func sleep(until deadline: Date) async throws {
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enum Outcome { case cancelled, elapsed, waiting([CheckedContinuation<Date, Never>]) }
                let outcome = state.withLock { state -> Outcome in
                    if state.cancelled.remove(id) != nil { return .cancelled }
                    if deadline <= state.now { return .elapsed }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    defer { state.idleWaiters = [] }
                    return .waiting(state.idleWaiters)
                }
                switch outcome {
                case .cancelled: continuation.resume(throwing: CancellationError())
                case .elapsed: continuation.resume()
                case .waiting(let waiters): waiters.forEach { $0.resume(returning: deadline) }
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                if let index = state.sleepers.firstIndex(where: { $0.id == id }) {
                    return state.sleepers.remove(at: index)
                }
                state.cancelled.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by interval: TimeInterval) {
        let woken = state.withLock { state -> [Sleeper] in
            state.now = state.now.addingTimeInterval(interval)
            let now = state.now
            let woken = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return woken
        }
        woken.forEach { $0.continuation.resume() }
    }

    /// Waits until something is asleep on this clock and returns its deadline.
    func nextSleep() async -> Date {
        await withCheckedContinuation { continuation in
            let deadline = state.withLock { state -> Date? in
                if let sleeper = state.sleepers.first { return sleeper.deadline }
                state.idleWaiters.append(continuation)
                return nil
            }
            if let deadline { continuation.resume(returning: deadline) }
        }
    }
}

/// Answers from a fixture or fails, and records every request.
final class ScriptedWeatherService: WeatherService {
    private struct State {
        var failsReports = false
        var failsAttribution = false
        var requests: [GeoPoint] = []
        var attributionRequests = 0
    }

    private let state = Mutex(State())
    private let clock: ManualClock
    let callsPerReport = 5

    init(clock: ManualClock, failing: Bool = false) {
        self.clock = clock
        state.withLock { $0.failsReports = failing; $0.failsAttribution = failing }
    }

    var requests: [GeoPoint] { state.withLock { $0.requests } }
    var attributionRequests: Int { state.withLock { $0.attributionRequests } }

    func setFailing(_ failing: Bool) {
        state.withLock { $0.failsReports = failing; $0.failsAttribution = failing }
    }

    func report(for location: GeoPoint) async throws -> WeatherReport {
        let fails = state.withLock { state in
            state.requests.append(location)
            return state.failsReports
        }
        if fails { throw URLError(.notConnectedToInternet) }
        return WeatherFixture.report(at: clock.now, location: location)
    }

    func attribution() async throws -> WeatherAttributionInfo {
        let fails = state.withLock { state in
            state.attributionRequests += 1
            return state.failsAttribution
        }
        if fails { throw URLError(.notConnectedToInternet) }
        return WeatherFixture.attribution
    }
}

/// Counts mark downloads and hands back fixed bytes.
final class MarkLoader: Sendable {
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private let count = Mutex(0)

    var downloads: Int { count.withLock { $0 } }

    var loader: WeatherDataLoader {
        { [self] _ in
            count.withLock { $0 += 1 }
            return Self.png
        }
    }
}
