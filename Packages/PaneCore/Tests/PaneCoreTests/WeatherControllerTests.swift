import Foundation
import Testing
@testable import PaneCore

private let start = WeatherFixture.local(2026, 11, 2, 14)
private let minute: TimeInterval = 60

@MainActor
private struct Harness {
    let clock: ManualClock
    let service: ScriptedWeatherService
    let cache: WeatherCache
    let store = InMemoryKeyValueStore()
    let marks = MarkLoader()
    let controller: WeatherController

    init(now: Date = start, failing: Bool = false, cache: WeatherCache = .inMemory(), location: GeoPoint? = WeatherFixture.chicago) {
        clock = ManualClock(now: now)
        service = ScriptedWeatherService(clock: clock, failing: failing)
        self.cache = cache
        controller = WeatherController(
            service: service,
            cache: cache,
            budget: CallBudget(store: store, calendar: WeatherFixture.calendar),
            clock: clock,
            loadData: marks.loader
        )
        controller.location = location
    }

    /// Starts the loop and waits until it first goes to sleep.
    func launch() async -> (task: Task<Void, Never>, wake: Date) {
        let controller = controller
        let task = Task { await controller.run() }
        return (task, await clock.nextSleep())
    }

    func advance(by interval: TimeInterval) async -> Date {
        clock.advance(by: interval)
        return await clock.nextSleep()
    }
}

private func stop(_ task: Task<Void, Never>) async {
    task.cancel()
    await task.value
}

@Suite("Weather controller", .timeLimit(.minutes(1)))
@MainActor
struct WeatherControllerTests {
    @Test func cachedReportShowsWhileEveryFetchFails() async {
        let cache = WeatherCache.inMemory()
        let cached = WeatherFixture.report(at: start)
        cache.save(cached)
        cache.save(WeatherFixture.attribution, fetchedAt: start.addingTimeInterval(-3600))
        cache.saveMark(MarkLoader.png)
        let harness = Harness(now: start.addingTimeInterval(20 * minute), failing: true, cache: cache)

        let (task, wake) = await harness.launch()
        let controller = harness.controller

        #expect(controller.report == cached)
        #expect(controller.attribution == WeatherFixture.attribution)
        #expect(controller.markImageData == MarkLoader.png)
        #expect(controller.lastFailure == harness.clock.now)
        #expect(controller.freshness(at: harness.clock.now) == .delayed(minutes: 20))
        #expect(controller.freshness(at: harness.clock.now).label == "Updated 20 min ago")
        #expect(harness.service.requests == [WeatherFixture.chicago])
        #expect(wake == harness.clock.now.addingTimeInterval(2 * minute))
        #expect(harness.service.attributionRequests == 0)
        #expect(harness.marks.downloads == 0)

        let secondWake = await harness.advance(by: 2 * minute)
        #expect(harness.service.requests.count == 2)
        #expect(secondWake == harness.clock.now.addingTimeInterval(4 * minute))
        #expect(controller.report == cached)

        _ = await harness.advance(by: 8 * minute)
        #expect(controller.freshness(at: harness.clock.now) == .stale(minutes: 30))
        await stop(task)
    }

    @Test func delayedTwentyMinutesAfterTheLastSuccess() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, wake) = await harness.launch()
        #expect(controller.report?.fetchedAt == start)
        #expect(controller.freshness(at: start) == .fresh)
        #expect(wake == start.addingTimeInterval(10 * minute))

        harness.service.setFailing(true)
        var wakes: [Date] = []
        wakes.append(await harness.advance(by: 10 * minute))
        wakes.append(await harness.advance(by: 2 * minute))
        wakes.append(await harness.advance(by: 4 * minute))
        #expect(wakes == [12, 16, 24].map { start.addingTimeInterval($0 * minute) })

        _ = await harness.advance(by: 4 * minute)
        #expect(harness.clock.now == start.addingTimeInterval(20 * minute))
        #expect(controller.report?.fetchedAt == start)
        #expect(controller.freshness(at: harness.clock.now) == .delayed(minutes: 20))
        #expect(controller.freshness(at: harness.clock.now).label == "Updated 20 min ago")

        harness.service.setFailing(false)
        let recovered = await harness.advance(by: 4 * minute)
        #expect(controller.lastFailure == nil)
        #expect(controller.freshness(at: harness.clock.now) == .fresh)
        #expect(recovered == harness.clock.now.addingTimeInterval(10 * minute))
        await stop(task)
    }

    @Test func locationChangeRefreshesPromptly() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, _) = await harness.launch()
        #expect(harness.service.requests == [WeatherFixture.chicago])

        controller.location = WeatherFixture.grantPark
        let wake = await harness.clock.nextSleep()
        #expect(harness.service.requests == [WeatherFixture.chicago, WeatherFixture.grantPark])
        #expect(controller.report?.location == WeatherFixture.grantPark)
        #expect(harness.clock.now == start)
        #expect(wake == start.addingTimeInterval(10 * minute))

        controller.location = WeatherFixture.grantPark
        _ = await harness.advance(by: minute)
        #expect(harness.service.requests.count == 2)
        await stop(task)
    }

    @Test func locationChangeDropsTheOtherPlacesReport() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, _) = await harness.launch()
        #expect(controller.report?.location == WeatherFixture.chicago)

        harness.service.setFailing(true)
        controller.location = WeatherFixture.grantPark
        #expect(controller.report == nil)
        _ = await harness.clock.nextSleep()
        #expect(controller.report == nil)
        #expect(controller.lastFailure != nil)
        #expect(controller.freshness == .none)
        await stop(task)
    }

    @Test func cacheFromAnotherPlaceIsNotShownWhileOffline() async {
        let cache = WeatherCache.inMemory()
        cache.save(WeatherFixture.report(at: start.addingTimeInterval(-3 * minute), location: WeatherFixture.grantPark))
        let harness = Harness(failing: true, cache: cache)
        let (task, _) = await harness.launch()
        #expect(harness.controller.report == nil)
        #expect(harness.service.requests == [WeatherFixture.chicago])
        await stop(task)
    }

    @Test func budgetCountsEveryAttempt() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, _) = await harness.launch()
        #expect(controller.callsThisMonth == 5)

        controller.location = WeatherFixture.grantPark
        _ = await harness.clock.nextSleep()
        #expect(controller.callsThisMonth == 10)

        harness.service.setFailing(true)
        _ = await harness.advance(by: 10 * minute)
        #expect(controller.callsThisMonth == 15)
        #expect(CallBudget(store: harness.store, calendar: WeatherFixture.calendar).calls(at: harness.clock.now) == 15)
        await stop(task)
    }

    @Test func refreshNowFetchesImmediately() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, _) = await harness.launch()
        _ = await harness.advance(by: 3 * minute)

        await controller.refreshNow()
        #expect(harness.service.requests.count == 2)
        #expect(controller.report?.fetchedAt == start.addingTimeInterval(3 * minute))
        let wake = await harness.clock.nextSleep()
        #expect(wake == start.addingTimeInterval(13 * minute))
        await stop(task)
    }

    @Test func refreshNowWithoutALocationDoesNothing() async {
        let harness = Harness(location: nil)
        await harness.controller.refreshNow()
        #expect(harness.service.requests.isEmpty)
        #expect(harness.controller.freshness(at: start) == .none)
    }

    @Test func noLocationWaitsUntilOneIsSet() async {
        let harness = Harness(location: nil)
        let (task, wake) = await harness.launch()
        #expect(harness.service.requests.isEmpty)
        #expect(wake == start.addingTimeInterval(10 * minute))

        harness.controller.location = WeatherFixture.chicago
        _ = await harness.clock.nextSleep()
        #expect(harness.service.requests == [WeatherFixture.chicago])
        await stop(task)
    }

    @Test func relaunchWithARecentCacheSpendsNoCalls() async {
        let cache = WeatherCache.inMemory()
        cache.save(WeatherFixture.report(at: start.addingTimeInterval(-3 * minute)))
        let harness = Harness(cache: cache)
        let (task, wake) = await harness.launch()
        #expect(harness.service.requests.isEmpty)
        #expect(harness.controller.callsThisMonth == 0)
        #expect(wake == start.addingTimeInterval(7 * minute))
        await stop(task)
    }

    @Test func cacheFromAnotherPlaceRefreshesAtOnce() async {
        let cache = WeatherCache.inMemory()
        cache.save(WeatherFixture.report(at: start.addingTimeInterval(-3 * minute), location: WeatherFixture.grantPark))
        let harness = Harness(cache: cache)
        let (task, _) = await harness.launch()
        #expect(harness.service.requests == [WeatherFixture.chicago])
        #expect(cache.loadReport()?.location == WeatherFixture.chicago)
        await stop(task)
    }

    @Test func attributionAtMostDailyAndTheMarkIsCached() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, _) = await harness.launch()
        #expect(controller.attribution == WeatherFixture.attribution)
        #expect(controller.markImageData == MarkLoader.png)
        #expect(harness.cache.loadMark() == MarkLoader.png)
        #expect(harness.cache.loadAttribution()?.fetchedAt == start)

        for _ in 0..<3 { _ = await harness.advance(by: 10 * minute) }
        #expect(harness.service.requests.count == 4)
        #expect(harness.service.attributionRequests == 1)
        #expect(harness.marks.downloads == 1)

        _ = await harness.advance(by: 24 * 3600)
        #expect(harness.service.attributionRequests == 2)
        #expect(harness.marks.downloads == 2)
        await stop(task)
    }

    @Test func missingAttributionIsRetriedWithTheNextRefresh() async {
        let harness = Harness(failing: true)
        let (task, _) = await harness.launch()
        #expect(harness.controller.attribution == nil)
        #expect(harness.service.attributionRequests == 1)

        harness.service.setFailing(false)
        _ = await harness.advance(by: 2 * minute)
        #expect(harness.service.attributionRequests == 2)
        #expect(harness.controller.attribution == WeatherFixture.attribution)
        #expect(harness.controller.markImageData == MarkLoader.png)
        await stop(task)
    }

    @Test func cancellingTheTaskEndsTheLoop() async {
        let harness = Harness()
        let (task, _) = await harness.launch()
        await stop(task)
        harness.clock.advance(by: 3600)
        #expect(harness.service.requests.count == 1)
    }
}
