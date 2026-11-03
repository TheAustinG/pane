import Foundation
import Testing
@testable import PaneCore

private let calendar = WeatherFixture.calendar
private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { WeatherFixture.local(year, month, day, hour, minute) }
private let december = local(2026, 12, 1, 0)
private let january = local(2027, 1, 1, 0)
private let callsPerReport = 5

/// Runs the policy across December (31 days) with the given outcome per attempt and counts the
/// calls the budget records.
private func simulateMonth(
    policy: RefreshPolicy = RefreshPolicy(),
    softLimit: Int = CallBudget.defaultSoftLimit,
    succeeds: (Int) -> Bool
) -> (calls: Int, attempts: [Date]) {
    let budget = CallBudget(store: InMemoryKeyValueStore(), calendar: calendar, softLimit: softLimit)
    var state = RefreshState()
    var attempts: [Date] = []
    var now = december
    while now < january {
        budget.record(callsPerReport, at: now)
        attempts.append(now)
        if succeeds(attempts.count - 1) { state.recordSuccess(at: now) } else { state.recordFailure(at: now) }
        now = policy.nextRefresh(after: state, overBudget: budget.isOverSoftLimit(at: now))!
    }
    return (budget.calls(at: december), attempts)
}

/// The most attempts any sequence of successes and failures can force in `minutes`, ignoring the
/// soft limit: a search over (minute, consecutive failures).
private func worstCaseAttempts(policy: RefreshPolicy, minutes: Int) -> Int {
    let steps = policy.backoff.count
    let delays = (0...steps).map { Int(policy.delay(afterFailures: $0) / 60) }
    let horizon = minutes + (delays.max() ?? 0) + 1
    var most = Array(repeating: Array(repeating: 0, count: steps + 1), count: horizon)
    for minute in stride(from: minutes - 1, through: 0, by: -1) {
        for failures in 0...steps {
            let afterFailure = min(failures + 1, steps)
            most[minute][failures] = 1 + max(
                most[minute + delays[0]][0],
                most[minute + delays[afterFailure]][afterFailure]
            )
        }
    }
    return most[0][0]
}

@Suite("Weather call budget")
struct WeatherCallBudgetTests {
    @Test func steadyMonthAtTenMinutes() {
        let month = simulateMonth { _ in true }
        #expect(month.calls == 31 * 24 * 6 * callsPerReport)
        #expect(month.calls == 22_320)
        #expect(month.calls < 50_000)
    }

    @Test func monthOfFailuresBacksOff() {
        let month = simulateMonth { _ in false }
        #expect(month.calls < 50_000)
        #expect(month.calls < simulateMonth { _ in true }.calls)
    }

    @Test func flakyMonthsStayUnderFiftyThousand() {
        let alternating = simulateMonth { $0.isMultiple(of: 2) }
        let successThenTwoFailures = simulateMonth { $0.isMultiple(of: 3) }
        #expect(alternating.calls == 37_200)
        #expect(successThenTwoFailures.calls == 41_850)
        #expect(successThenTwoFailures.calls < CallBudget.defaultSoftLimit)
    }

    @Test func worstCaseOverEveryOutcomeSequenceStaysUnderFiftyThousand() {
        let attempts = worstCaseAttempts(policy: RefreshPolicy(), minutes: 31 * 24 * 60)
        #expect(attempts == 8_371)
        #expect(attempts * callsPerReport < 50_000)
    }

    @Test func softLimitStretchesTheInterval() {
        let month = simulateMonth(softLimit: 10_000) { _ in true }
        let crossing = 10_000 / callsPerReport
        let gaps = zip(month.attempts, month.attempts.dropFirst()).map { $1.timeIntervalSince($0) }
        #expect(gaps.prefix(crossing - 1).allSatisfy { $0 == 10 * 60 })
        #expect(gaps.dropFirst(crossing - 1).allSatisfy { $0 == 30 * 60 })
        #expect(month.calls < 15_000)
    }

    @Test func countResetsWhenTheMonthTurnsOver() {
        let budget = CallBudget(store: InMemoryKeyValueStore(), calendar: calendar)
        let lastMinuteOfNovember = local(2026, 11, 30, 23, 59)
        budget.record(5, at: lastMinuteOfNovember)
        budget.record(5, at: lastMinuteOfNovember)
        #expect(budget.calls(at: lastMinuteOfNovember) == 10)
        #expect(budget.calls(at: december) == 0)
        #expect(budget.record(5, at: december) == 5)
        #expect(budget.calls(at: lastMinuteOfNovember) == 0)
    }

    @Test func monthFollowsTheInjectedTimeZone() {
        let budget = CallBudget(store: InMemoryKeyValueStore(), calendar: calendar)
        let lateNovemberInChicago = utc("2026-12-01T05:30:00Z")
        #expect(budget.month(of: lateNovemberInChicago) == "2026-11")
        #expect(budget.month(of: utc("2026-12-01T06:00:00Z")) == "2026-12")
    }

    @Test func softLimitFlag() {
        let budget = CallBudget(store: InMemoryKeyValueStore(), calendar: calendar, softLimit: 10)
        budget.record(5, at: december)
        #expect(!budget.isOverSoftLimit(at: december))
        budget.record(5, at: december)
        #expect(budget.isOverSoftLimit(at: december))
        #expect(CallBudget.defaultSoftLimit == 45_000)
    }

    @Test func persistsThroughUserDefaults() throws {
        let suite = "pane.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        CallBudget(store: UserDefaultsKeyValueStore(defaults), calendar: calendar).record(15, at: december)
        let reopened = CallBudget(store: UserDefaultsKeyValueStore(defaults), calendar: calendar)
        #expect(reopened.calls(at: december) == 15)
    }

    @Test func recordingNothingWritesNothing() {
        let store = InMemoryKeyValueStore()
        CallBudget(store: store, calendar: calendar).record(0, at: december)
        #expect(store.data(forKey: "weather.callBudget") == nil)
    }
}
