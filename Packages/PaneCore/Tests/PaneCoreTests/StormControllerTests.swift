import Foundation
import Testing
@testable import PaneCore

private let start = WeatherFixture.local(2026, 11, 2, 14, 10)
private let minute: TimeInterval = 60

@MainActor
private struct Harness {
    let clock: ManualClock
    let service = StormWeatherService()
    let weather: WeatherController
    let storm: StormController

    init(simulation: StormSimulation? = nil) {
        clock = ManualClock(now: start)
        weather = WeatherController(
            service: service,
            cache: .inMemory(),
            budget: CallBudget(store: InMemoryKeyValueStore(), calendar: WeatherFixture.calendar),
            clock: clock,
            loadData: MarkLoader().loader
        )
        weather.location = WeatherFixture.chicago
        storm = StormController(weather: weather, clock: clock, simulation: simulation)
    }

    /// Makes `report` the weather controller's report, as a refresh would.
    func publish(_ report: WeatherReport) async {
        service.set(report)
        await weather.refreshNow()
    }

    /// Publishes a report fetched now while the loop runs, and waits for the loop to sleep again.
    func publishWhileRunning(alerts: [WeatherAlertInfo] = [], chance: Double = 0) async -> Date {
        await publish(StormFixture.report(at: clock.now, alerts: alerts, chance: chance))
        return await clock.nextSleep()
    }

    func launch() async -> (task: Task<Void, Never>, wake: Date) {
        let storm = storm
        let task = Task { await storm.run() }
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

@Suite("Storm controller", .timeLimit(.minutes(1)))
@MainActor
struct StormControllerTests {
    @Test func runFollowsTheReportAtOnceAndTheClockEveryMinute() async {
        let harness = Harness()
        let storm = harness.storm
        await harness.publish(StormFixture.report(at: start))
        let (task, wake) = await harness.launch()
        #expect(storm.state == .calm)
        #expect(wake == start.addingTimeInterval(minute))

        let alertWake = await harness.publishWhileRunning(alerts: [StormFixture.alert("a")])
        #expect(harness.clock.now == start)
        #expect(storm.state.reasons == [.alert])
        #expect(storm.state.alerts.map(\.id) == ["a"])
        #expect(storm.isTakeoverActive)
        #expect(alertWake == start.addingTimeInterval(minute))

        _ = await harness.publishWhileRunning()
        #expect(storm.state.isActive)
        #expect(storm.state.alerts.isEmpty)

        for _ in 1...19 { _ = await harness.advance(by: minute) }
        #expect(storm.state.isActive)
        let calmWake = await harness.advance(by: minute)
        #expect(storm.state == .calm)
        #expect(calmWake == start.addingTimeInterval(21 * minute))
        await stop(task)
    }

    @Test func aDismissedRainStormReturnsOnlyAfterGoingCalm() async {
        let harness = Harness()
        let storm = harness.storm
        await harness.publish(StormFixture.report(at: start, chance: 0.9))
        let (task, _) = await harness.launch()
        #expect(storm.isTakeoverActive)

        storm.dismiss()
        #expect(storm.isDismissed)
        #expect(storm.state.isActive)
        #expect(!storm.isTakeoverActive)

        _ = await harness.publishWhileRunning(chance: 0.9)
        #expect(!storm.isTakeoverActive)

        _ = await harness.publishWhileRunning()
        for _ in 1...20 { _ = await harness.advance(by: minute) }
        #expect(storm.state == .calm)
        #expect(!storm.isDismissed)

        _ = await harness.publishWhileRunning(chance: 0.6)
        #expect(storm.isTakeoverActive)
        await stop(task)
    }

    @Test func aDismissedWarningStaysHiddenAcrossADataGap() async {
        let harness = Harness()
        let storm = harness.storm
        await harness.publish(StormFixture.report(at: start, alerts: [StormFixture.alert("a")]))
        let (task, _) = await harness.launch()
        storm.dismiss()

        for _ in 1...80 { _ = await harness.advance(by: minute) }
        #expect(storm.state == .calm)
        #expect(!storm.isDismissed)

        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("a")])
        #expect(storm.state.reasons == [.alert])
        #expect(storm.isDismissed)
        #expect(!storm.isTakeoverActive)

        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("a"), StormFixture.alert("b")])
        #expect(storm.isTakeoverActive)
        await stop(task)
    }

    @Test func rainJoiningAStormHiddenByAnEarlierDismissalShowsIt() async {
        let harness = Harness()
        let storm = harness.storm
        await harness.publish(StormFixture.report(at: start, alerts: [StormFixture.alert("a")]))
        let (task, _) = await harness.launch()
        storm.dismiss()
        _ = await harness.publishWhileRunning()
        for _ in 1...20 { _ = await harness.advance(by: minute) }
        #expect(storm.state == .calm)

        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("a")])
        #expect(!storm.isTakeoverActive)
        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("a")], chance: 0.6)
        #expect(storm.isTakeoverActive)
        await stop(task)
    }

    @Test func rainJoiningADismissedStormKeepsItHidden() async {
        let harness = Harness()
        let storm = harness.storm
        await harness.publish(StormFixture.report(at: start, alerts: [StormFixture.alert("a")]))
        let (task, _) = await harness.launch()
        storm.dismiss()

        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("a")], chance: 0.6)
        #expect(storm.state.reasons == [.alert, .hourlyChance])
        #expect(!storm.isTakeoverActive)
        _ = await harness.publishWhileRunning(chance: 0.6)
        #expect(!storm.isTakeoverActive)
        await stop(task)
    }

    @Test func aDismissedIDIsForgottenAfterADayUnseen() async {
        let harness = Harness()
        let storm = harness.storm
        await harness.publish(StormFixture.report(at: start, alerts: [StormFixture.alert("a")]))
        let (task, _) = await harness.launch()
        storm.dismiss()
        _ = await harness.publishWhileRunning()
        _ = await harness.advance(by: 24 * 3600)
        #expect(storm.state == .calm)

        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("a")])
        #expect(storm.isTakeoverActive)
        await stop(task)
    }

    @Test func aDismissedIDSeenWithinADayStaysDismissed() async {
        let harness = Harness()
        let storm = harness.storm
        await harness.publish(StormFixture.report(at: start, alerts: [StormFixture.alert("a")]))
        let (task, _) = await harness.launch()
        storm.dismiss()
        _ = await harness.publishWhileRunning()

        _ = await harness.advance(by: 20 * 3600)
        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("a")])
        #expect(!storm.isTakeoverActive)
        _ = await harness.publishWhileRunning()

        _ = await harness.advance(by: 10 * 3600)
        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("a")])
        #expect(storm.state.isActive)
        #expect(!storm.isTakeoverActive)
        await stop(task)
    }

    @Test func onlyAnAlertWithANewIDShowsTheTakeoverAgain() async {
        let harness = Harness()
        let storm = harness.storm
        await harness.publish(StormFixture.report(at: start, alerts: [StormFixture.alert("a")], chance: 0.9))
        let (task, _) = await harness.launch()
        storm.dismiss()

        _ = await harness.publishWhileRunning(chance: 0.9)
        #expect(!storm.isTakeoverActive)
        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("a")], chance: 0.9)
        #expect(!storm.isTakeoverActive)

        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("a"), StormFixture.alert("b", severity: "extreme")], chance: 0.9)
        #expect(storm.isTakeoverActive)
        #expect(!storm.isDismissed)
        #expect(storm.state.alerts.map(\.id) == ["b", "a"])

        storm.dismiss()
        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("b", severity: "extreme")], chance: 0.9)
        #expect(!storm.isTakeoverActive)

        let advisory = StormFixture.alert("c", severity: "moderate", summary: "Wind Advisory")
        _ = await harness.publishWhileRunning(alerts: [StormFixture.alert("b", severity: "extreme"), advisory], chance: 0.9)
        #expect(storm.state.alerts.map(\.id) == ["b", "c"])
        #expect(!storm.isTakeoverActive)
        await stop(task)
    }

    @Test func dismissWhileCalmDoesNotHideTheNextStorm() async {
        let harness = Harness()
        let storm = harness.storm
        await harness.publish(StormFixture.report(at: start))
        let (task, _) = await harness.launch()
        storm.dismiss()
        #expect(!storm.isDismissed)

        _ = await harness.publishWhileRunning(chance: 0.6)
        #expect(storm.isTakeoverActive)
        #expect(storm.state.reasons == [.hourlyChance])
        await stop(task)
    }

    @Test func simulationChangesStateAtOnce() {
        let harness = Harness()
        let storm = harness.storm
        #expect(storm.state == .calm)

        storm.simulation = .storm
        #expect(storm.state == StormState(isActive: true, reasons: [.minutePrecipitation], alerts: []))
        #expect(storm.isTakeoverActive)

        storm.simulation = .alert
        #expect(storm.state == StormState(isActive: true, reasons: [.alert], alerts: [StormController.sampleAlert]))

        storm.simulation = nil
        #expect(storm.state == .calm)
        #expect(!storm.isTakeoverActive)
    }

    @Test func launchSimulationIsActiveBeforeRunStarts() {
        let harness = Harness(simulation: .alert)
        #expect(harness.storm.isTakeoverActive)
        #expect(harness.storm.state.alerts == [StormController.sampleAlert])
        #expect(StormReason.allCases.map(\.rawValue) == ["alert", "minutePrecipitation", "hourlyChance"])
    }

    @Test func dismissDuringASimulationClearsIt() async {
        let harness = Harness(simulation: .storm)
        let storm = harness.storm
        storm.dismiss()
        #expect(storm.simulation == nil)
        #expect(storm.state == .calm)
        #expect(!storm.isDismissed)
    }

    @Test func aSimulationShowsAfterADismissedStorm() async {
        let harness = Harness()
        let storm = harness.storm
        await harness.publish(StormFixture.report(at: start, alerts: [StormFixture.alert("a")]))
        storm.evaluate()
        storm.dismiss()
        #expect(!storm.isTakeoverActive)

        storm.simulation = .storm
        #expect(storm.isTakeoverActive)
        storm.dismiss()
        #expect(storm.simulation == nil)
        #expect(storm.state.reasons == [.alert])
        #expect(storm.isDismissed)
        #expect(!storm.isTakeoverActive)
    }

    @Test func aRefreshFailingForAnHourEndsStormMode() async {
        let harness = Harness()
        let storm = harness.storm
        await harness.publish(StormFixture.report(at: start, alerts: [StormFixture.alert("a")], chance: 0.9))
        let (task, _) = await harness.launch()
        #expect(storm.state.reasons == [.alert, .hourlyChance])

        for _ in 1...79 { _ = await harness.advance(by: minute) }
        #expect(storm.state.isActive)
        _ = await harness.advance(by: minute)
        #expect(storm.state == .calm)
        await stop(task)
    }

    @Test func cancellingTheTaskEndsTheLoop() async {
        let harness = Harness()
        await harness.publish(StormFixture.report(at: start))
        let (task, _) = await harness.launch()
        await stop(task)
        await harness.publish(StormFixture.report(at: start, alerts: [StormFixture.alert("a")]))
        harness.clock.advance(by: 3600)
        #expect(harness.storm.state == .calm)
    }
}
