import Foundation

/// When to fetch: every `interval` while fetches work, backing off after failures, and slower once
/// the month's calls pass the budget's soft limit.
public struct RefreshPolicy: Hashable, Sendable {
    public var interval: TimeInterval
    /// The wait after one, two, three or more consecutive failures; the last step repeats.
    public var backoff: [TimeInterval]
    public var staleAfter: TimeInterval
    /// The shortest wait once the month's calls pass the budget's soft limit.
    public var overBudgetInterval: TimeInterval

    public static let minimumDelay: TimeInterval = 60

    public init(
        interval: TimeInterval = 10 * 60,
        backoff: [TimeInterval] = [2 * 60, 4 * 60, 8 * 60, 15 * 60],
        staleAfter: TimeInterval = 30 * 60,
        overBudgetInterval: TimeInterval = 30 * 60
    ) {
        self.interval = interval
        self.backoff = backoff
        self.staleAfter = staleAfter
        self.overBudgetInterval = overBudgetInterval
    }

    public func delay(afterFailures failures: Int, overBudget: Bool = false) -> TimeInterval {
        let base = failures <= 0 || backoff.isEmpty ? interval : backoff[min(failures, backoff.count) - 1]
        return max(base, overBudget ? overBudgetInterval : 0, Self.minimumDelay)
    }

    /// Nil until the first attempt, which is due at once.
    public func nextRefresh(after state: RefreshState, overBudget: Bool = false) -> Date? {
        state.lastAttempt.map { $0.addingTimeInterval(delay(afterFailures: state.consecutiveFailures, overBudget: overBudget)) }
    }

    /// An attempt stamped after `date` means the clock went back, so waiting on it could stall.
    public func isDue(_ state: RefreshState, at date: Date, overBudget: Bool = false) -> Bool {
        guard let lastAttempt = state.lastAttempt, lastAttempt <= date,
              let next = nextRefresh(after: state, overBudget: overBudget) else { return true }
        return next <= date
    }

    public func freshness(fetchedAt: Date?, lastAttemptFailed: Bool, at date: Date) -> Freshness {
        guard let fetchedAt else { return .none }
        let age = date.timeIntervalSince(fetchedAt)
        // A negative age means the app clock is pinned before the fetch by `-now`.
        guard age >= 0 else { return .fresh }
        let minutes = Int(age / 60)
        if age >= staleAfter { return .stale(minutes: minutes) }
        return lastAttemptFailed ? .delayed(minutes: minutes) : .fresh
    }
}

/// What the policy needs to know about past attempts.
public struct RefreshState: Hashable, Sendable {
    public var lastAttempt: Date?
    public var consecutiveFailures: Int

    public init(lastAttempt: Date? = nil, consecutiveFailures: Int = 0) {
        self.lastAttempt = lastAttempt
        self.consecutiveFailures = consecutiveFailures
    }

    public var lastAttemptFailed: Bool { consecutiveFailures > 0 }

    public mutating func recordSuccess(at date: Date) {
        lastAttempt = date
        consecutiveFailures = 0
    }

    public mutating func recordFailure(at date: Date) {
        lastAttempt = date
        consecutiveFailures += 1
    }
}
