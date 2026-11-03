import Foundation
import Testing
@testable import PaneCore

private let start = WeatherFixture.local(2026, 11, 2, 14)
private let minute: TimeInterval = 60

@Suite("Weather refresh policy")
struct WeatherRefreshPolicyTests {
    let policy = RefreshPolicy()

    @Test func firstAttemptIsDueAtOnce() {
        let state = RefreshState()
        #expect(policy.nextRefresh(after: state) == nil)
        #expect(policy.isDue(state, at: start))
    }

    @Test func refreshesEveryTenMinutes() {
        var state = RefreshState()
        var now = start
        for _ in 0..<6 {
            state.recordSuccess(at: now)
            #expect(!policy.isDue(state, at: now.addingTimeInterval(10 * minute - 1)))
            #expect(policy.isDue(state, at: now.addingTimeInterval(10 * minute)))
            now = policy.nextRefresh(after: state)!
        }
        #expect(now == start.addingTimeInterval(60 * minute))
    }

    @Test func backsOffAfterFailuresAndCaps() {
        var state = RefreshState()
        var now = start
        var waits: [TimeInterval] = []
        for _ in 0..<7 {
            state.recordFailure(at: now)
            let next = policy.nextRefresh(after: state)!
            waits.append(next.timeIntervalSince(now) / minute)
            now = next
        }
        #expect(waits == [2, 4, 8, 15, 15, 15, 15])
    }

    @Test func recoversAfterASuccess() {
        var state = RefreshState()
        for offset in 0..<5 { state.recordFailure(at: start.addingTimeInterval(Double(offset) * minute)) }
        #expect(state.lastAttemptFailed)
        let recovered = start.addingTimeInterval(30 * minute)
        state.recordSuccess(at: recovered)
        #expect(state.consecutiveFailures == 0)
        #expect(policy.nextRefresh(after: state) == recovered.addingTimeInterval(10 * minute))
        state.recordFailure(at: recovered.addingTimeInterval(10 * minute))
        #expect(policy.delay(afterFailures: state.consecutiveFailures) == 2 * minute)
    }

    @Test func neverFasterThanOnceAMinute() {
        let hasty = RefreshPolicy(interval: 5, backoff: [1, 10, 30])
        #expect(hasty.delay(afterFailures: 0) == minute)
        #expect((1...4).map { hasty.delay(afterFailures: $0) } == [minute, minute, minute, minute])
        #expect(RefreshPolicy(backoff: []).delay(afterFailures: 3) == 10 * minute)
    }

    @Test func stretchesPastTheSoftLimit() {
        #expect(policy.delay(afterFailures: 0, overBudget: true) == 30 * minute)
        #expect(policy.delay(afterFailures: 1, overBudget: true) == 30 * minute)
        var state = RefreshState()
        state.recordSuccess(at: start)
        #expect(!policy.isDue(state, at: start.addingTimeInterval(20 * minute), overBudget: true))
        #expect(policy.isDue(state, at: start.addingTimeInterval(30 * minute), overBudget: true))
    }

    @Test func anAttemptStampedInTheFutureIsDue() {
        var state = RefreshState()
        state.recordSuccess(at: start.addingTimeInterval(3600))
        #expect(policy.isDue(state, at: start))
    }
}

@Suite("Weather freshness")
struct WeatherFreshnessTests {
    let policy = RefreshPolicy()

    private func freshness(age minutes: Double, failed: Bool) -> Freshness {
        policy.freshness(fetchedAt: start, lastAttemptFailed: failed, at: start.addingTimeInterval(minutes * minute))
    }

    @Test func noDataIsNone() {
        #expect(policy.freshness(fetchedAt: nil, lastAttemptFailed: true, at: start) == .none)
        #expect(Freshness.none.label == nil)
    }

    @Test func recentSuccessIsFresh() {
        #expect(freshness(age: 0, failed: false) == .fresh)
        #expect(freshness(age: 29.9, failed: false) == .fresh)
        #expect(Freshness.fresh.label == nil)
    }

    @Test func failedRefreshIsDelayed() {
        #expect(freshness(age: 20, failed: true) == .delayed(minutes: 20))
        #expect(freshness(age: 20.9, failed: true) == .delayed(minutes: 20))
        #expect(freshness(age: 29.9, failed: true) == .delayed(minutes: 29))
        #expect(Freshness.delayed(minutes: 20).label == "Updated 20 min ago")
        #expect(Freshness.delayed(minutes: 0).label == "Updated just now")
    }

    @Test func staleAtThirtyMinutesEitherWay() {
        #expect(freshness(age: 30, failed: false) == .stale(minutes: 30))
        #expect(freshness(age: 30, failed: true) == .stale(minutes: 30))
        #expect(freshness(age: 95, failed: true) == .stale(minutes: 95))
        #expect(Freshness.stale(minutes: 30).label == "Updated 30 min ago")
        #expect(Freshness.stale(minutes: 95).label == "Updated 1 h ago")
        #expect(Freshness.stale(minutes: 3 * 24 * 60).label == "Updated 3 d ago")
    }

    @Test func clockPinnedBeforeTheFetchIsFresh() {
        #expect(freshness(age: -90, failed: true) == .fresh)
        #expect(freshness(age: -1, failed: false) == .fresh)
    }
}
