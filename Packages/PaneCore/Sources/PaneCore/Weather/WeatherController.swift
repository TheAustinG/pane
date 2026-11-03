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
    /// When the last attempt failed; nil once one succeeds.
    public private(set) var lastFailure: Date?
    /// Billable WeatherKit calls counted this calendar month.
    public private(set) var callsThisMonth: Int
    /// Changing it wakes the refresh loop to fetch the new place, and drops a report for any other
    /// place so the cards never show the wrong city while that fetch is pending or failing.
    public var location: GeoPoint? {
        didSet {
            guard location != oldValue else { return }
            if report?.location != location {
                report = nil
                lastFailure = nil
            }
            wakeLoop()
        }
    }

    static let attributionLifetime: TimeInterval = 24 * 3600

    @ObservationIgnored private let service: any WeatherService
    @ObservationIgnored private let cache: WeatherCache
    @ObservationIgnored private let budget: CallBudget
    @ObservationIgnored private let policy: RefreshPolicy
    @ObservationIgnored private let clock: any WeatherClock
    @ObservationIgnored private let loadData: WeatherDataLoader
    @ObservationIgnored private var refreshState = RefreshState()
    /// Where the last attempt fetched; a different `location` is due at once.
    @ObservationIgnored private var attemptedLocation: GeoPoint?
    @ObservationIgnored private var attributionFetchedAt: Date?
    @ObservationIgnored private var hasLoadedCache = false
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var sleeper: Task<Void, any Error>?

    public init(
        service: any WeatherService,
        cache: WeatherCache = WeatherCache(directory: WeatherCache.defaultDirectory),
        budget: CallBudget = CallBudget(),
        policy: RefreshPolicy = RefreshPolicy(),
        clock: any WeatherClock = SystemWeatherClock(),
        loadData: @escaping WeatherDataLoader = WeatherDownload.data(from:)
    ) {
        self.service = service
        self.cache = cache
        self.budget = budget
        self.policy = policy
        self.clock = clock
        self.loadData = loadData
        callsThisMonth = budget.calls(at: clock.now)
    }

    /// Shows the cached report at once, then refreshes whenever due. Runs until the calling task
    /// is cancelled.
    public func run() async {
        loadCache()
        while !Task.isCancelled {
            updateCallCount()
            if isDue(at: clock.now) {
                await refresh()
            } else {
                await sleep(until: nextWake(at: clock.now))
            }
        }
    }

    /// Fetches now whatever the schedule says, joining a fetch already under way for this place.
    public func refreshNow() async {
        if let inFlight {
            await inFlight.value
            if attemptedLocation == location { return }
        }
        await refresh()
    }

    /// Measured on the controller's clock: a pinned or scrubbed app clock says nothing about data age.
    public var freshness: Freshness {
        freshness(at: clock.now)
    }

    public func freshness(at date: Date) -> Freshness {
        policy.freshness(fetchedAt: report?.fetchedAt, lastAttemptFailed: lastFailure != nil, at: date)
    }

    private func loadCache() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true
        let now = clock.now
        if report == nil, let cached = cache.loadReport(), cached.location == location {
            report = cached
            // A recent fetch for this place counts as the last attempt, so a relaunch spends no calls.
            let age = now.timeIntervalSince(cached.fetchedAt)
            if age >= 0, age < policy.interval {
                refreshState.recordSuccess(at: cached.fetchedAt)
                attemptedLocation = cached.location
            }
        }
        if attribution == nil, let saved = cache.loadAttribution() {
            attribution = saved.info
            attributionFetchedAt = saved.fetchedAt
        }
        if markImageData == nil {
            markImageData = cache.loadMark()
        }
    }

    private var isOverBudget: Bool {
        budget.isOverSoftLimit(at: clock.now)
    }

    private func isDue(at now: Date) -> Bool {
        guard let location else { return false }
        if location != attemptedLocation { return true }
        return policy.isDue(refreshState, at: now, overBudget: isOverBudget)
    }

    /// Never later than one interval away, so a month rollover or a clock change is noticed.
    private func nextWake(at now: Date) -> Date {
        let latest = now.addingTimeInterval(policy.interval)
        guard location != nil, let next = policy.nextRefresh(after: refreshState, overBudget: isOverBudget) else {
            return latest
        }
        return min(next, latest)
    }

    private func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        guard let target = location else { return }
        let task = Task {
            await fetch(target)
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func fetch(_ target: GeoPoint) async {
        let started = clock.now
        attemptedLocation = target
        budget.record(service.callsPerReport, at: started)
        updateCallCount()
        do {
            let fresh = try await service.report(for: target)
            report = fresh
            lastFailure = nil
            refreshState.recordSuccess(at: started)
            cache.save(fresh)
        } catch {
            refreshState.recordFailure(at: started)
            lastFailure = clock.now
        }
        await refreshAttributionIfDue()
        // A fetch started by `refreshNow` moves the schedule, so the sleeping loop recomputes it.
        wakeLoop()
    }

    private func refreshAttributionIfDue() async {
        let now = clock.now
        var renewed = false
        if attributionIsDue(at: now), let fresh = try? await service.attribution() {
            attribution = fresh
            attributionFetchedAt = now
            cache.save(fresh, fetchedAt: now)
            renewed = true
        }
        guard let attribution, renewed || markImageData == nil else { return }
        if let data = try? await loadData(attribution.combinedMarkDarkURL), !data.isEmpty {
            markImageData = data
            cache.saveMark(data)
        }
    }

    private func attributionIsDue(at now: Date) -> Bool {
        guard attribution != nil, let fetchedAt = attributionFetchedAt else { return true }
        let age = now.timeIntervalSince(fetchedAt)
        return age < 0 || age >= Self.attributionLifetime
    }

    private func updateCallCount() {
        let calls = budget.calls(at: clock.now)
        if calls != callsThisMonth { callsThisMonth = calls }
    }

    private func sleep(until deadline: Date) async {
        let clock = clock
        let task = Task { try await clock.sleep(until: deadline) }
        sleeper = task
        await withTaskCancellationHandler {
            _ = try? await task.value
        } onCancel: {
            task.cancel()
        }
        sleeper = nil
    }

    private func wakeLoop() {
        sleeper?.cancel()
    }
}
