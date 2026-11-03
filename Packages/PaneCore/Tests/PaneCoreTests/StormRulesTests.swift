import Foundation
import Testing
@testable import PaneCore

private let now = WeatherFixture.local(2026, 11, 2, 14, 10)
private let thisHour = WeatherFixture.local(2026, 11, 2, 14)
private let minute: TimeInterval = 60
private let hour: TimeInterval = 3600

struct StormTriggerCase: Sendable, CustomTestStringConvertible {
    let name: String
    let report: WeatherReport?
    let previous: StormEvaluation
    let expected: Set<StormReason>

    init(_ name: String, _ report: WeatherReport?, after previous: StormEvaluation = .calm, _ expected: Set<StormReason>) {
        self.name = name
        self.report = report
        self.previous = previous
        self.expected = expected
    }

    var testDescription: String { name }
}

/// Storm mode held on by `reasons`, its hold running out now unless a rule holds.
private func storm(_ reasons: Set<StormReason>) -> StormEvaluation {
    StormEvaluation(state: StormState(isActive: true, reasons: reasons, alerts: []), lastSignal: now.addingTimeInterval(-20 * minute))
}

private func report(
    fetchedAt: Date = now,
    alerts: [WeatherAlertInfo] = [],
    minutes: [MinuteForecast]? = nil,
    chance: Double = 0,
    hourStarting: Date? = nil
) -> WeatherReport {
    StormFixture.report(at: now, fetchedAt: fetchedAt, alerts: alerts, minutes: minutes, chance: chance) { date in
        hourStarting.map { $0 == date } ?? true
    }
}

/// Defaults under test: only extreme and severe alerts turn storm mode on; the minute and hourly rules
/// turn it on at a 50 percent chance, and a rule already holding it on keeps holding down to 30
/// percent; the minute rule needs 3 minutes at that chance with any intensity in the next hour
/// (intensity only guards against chance alone, since its unit conversion is unverified); the hourly
/// rule looks at the hour under way and any starting within 60 minutes; storm mode ends 20 minutes
/// after the last rule held; reports older than 60 minutes count for nothing.
@Suite("Storm rules")
struct StormRulesTests {
    static let triggers: [StormTriggerCase] = [
        StormTriggerCase("a dry report", report(), []),
        StormTriggerCase("no report", nil, []),
        StormTriggerCase("a severe warning", report(alerts: [StormFixture.alert("a", severity: "severe")]), [.alert]),
        StormTriggerCase("an extreme warning", report(alerts: [StormFixture.alert("a", severity: "extreme")]), [.alert]),
        StormTriggerCase("a minor Heat Advisory alone", report(alerts: [StormFixture.alert("a", severity: "minor", summary: "Heat Advisory")]), []),
        StormTriggerCase("a minor Frost Advisory alone", report(alerts: [StormFixture.alert("a", severity: "minor", summary: "Frost Advisory")]), []),
        StormTriggerCase("a moderate Wind Advisory alone", report(alerts: [StormFixture.alert("a", severity: "moderate", summary: "Wind Advisory")]), []),
        StormTriggerCase("an Air Quality Alert of unknown severity alone", report(alerts: [StormFixture.alert("a", severity: "unknown", summary: "Air Quality Alert")]), []),
        StormTriggerCase(
            "a warning among advisories",
            report(alerts: [StormFixture.alert("a", severity: "minor"), StormFixture.alert("b", severity: "severe")]),
            [.alert]
        ),
        StormTriggerCase("three wet minutes at 50 percent", report(minutes: StormFixture.minutes(from: now, wet: 20..<23, chance: 0.5)), [.minutePrecipitation]),
        StormTriggerCase("two wet minutes are noise", report(minutes: StormFixture.minutes(from: now, wet: 20..<22)), []),
        StormTriggerCase("wet minutes at 49 percent", report(minutes: StormFixture.minutes(from: now, wet: 0..<60, chance: 0.49)), []),
        StormTriggerCase("chance without intensity", report(minutes: StormFixture.minutes(from: now, wet: 0..<60, intensity: 0)), []),
        StormTriggerCase("a trace of intensity counts", report(minutes: StormFixture.minutes(from: now, wet: 40..<45, intensity: 0.01)), [.minutePrecipitation]),
        StormTriggerCase("the minute under way counts", report(minutes: StormFixture.minutes(from: now.addingTimeInterval(-30), wet: 0..<3)), [.minutePrecipitation]),
        StormTriggerCase("minutes already over", report(minutes: StormFixture.minutes(from: now.addingTimeInterval(-10 * minute), wet: 0..<9)), []),
        StormTriggerCase("minutes past the next hour", report(minutes: StormFixture.minutes(from: now.addingTimeInterval(50 * minute), wet: 10..<60)), []),
        StormTriggerCase("no minute data", report(minutes: nil), []),
        StormTriggerCase("the hour under way at 50 percent", report(chance: 0.5, hourStarting: thisHour), [.hourlyChance]),
        StormTriggerCase("the hour under way at 49 percent", report(chance: 0.49, hourStarting: thisHour), []),
        StormTriggerCase("the next hour, starting in 50 minutes, at 60 percent", report(chance: 0.6, hourStarting: thisHour.addingTimeInterval(hour)), [.hourlyChance]),
        StormTriggerCase("an hour starting in 110 minutes", report(chance: 0.9, hourStarting: thisHour.addingTimeInterval(2 * hour)), []),
        StormTriggerCase("the hour already over", report(chance: 0.9, hourStarting: thisHour.addingTimeInterval(-hour)), []),
        StormTriggerCase(
            "every rule at once",
            report(alerts: [StormFixture.alert("a")], minutes: StormFixture.minutes(from: now, wet: 0..<10), chance: 0.9),
            [.alert, .minutePrecipitation, .hourlyChance]
        ),
        StormTriggerCase("an alert 59 min old", report(fetchedAt: now.addingTimeInterval(-59 * minute), alerts: [StormFixture.alert("a")]), [.alert]),
        StormTriggerCase("an alert 61 min old", report(fetchedAt: now.addingTimeInterval(-61 * minute), alerts: [StormFixture.alert("a")]), []),
        StormTriggerCase("wet minutes 61 min old", report(fetchedAt: now.addingTimeInterval(-61 * minute), minutes: StormFixture.minutes(from: now, wet: 0..<60)), []),
        StormTriggerCase("an hourly chance 61 min old", report(fetchedAt: now.addingTimeInterval(-61 * minute), chance: 0.9), []),
        StormTriggerCase("a report from a clock that went back", report(fetchedAt: now.addingTimeInterval(hour), alerts: [StormFixture.alert("a")]), [.alert]),
        StormTriggerCase("35 percent hourly while the hourly rule holds", report(chance: 0.35), after: storm([.hourlyChance]), [.hourlyChance]),
        StormTriggerCase("29 percent hourly while the hourly rule holds", report(chance: 0.29), after: storm([.hourlyChance]), []),
        StormTriggerCase("35 percent hourly once an alert storm ends", report(chance: 0.35), after: storm([.alert]), []),
        StormTriggerCase("35 percent hourly while only the minute rule holds", report(chance: 0.35), after: storm([.minutePrecipitation]), []),
        StormTriggerCase("50 percent hourly after an alert storm", report(chance: 0.5), after: storm([.alert]), [.hourlyChance]),
        StormTriggerCase(
            "35 percent minutes while the minute rule holds",
            report(minutes: StormFixture.minutes(from: now, wet: 0..<10, chance: 0.35)),
            after: storm([.minutePrecipitation]),
            [.minutePrecipitation]
        ),
        StormTriggerCase(
            "35 percent minutes while only the hourly rule holds",
            report(minutes: StormFixture.minutes(from: now, wet: 0..<10, chance: 0.35)),
            after: storm([.hourlyChance]),
            []
        ),
        StormTriggerCase(
            "35 percent minutes and hourly once an alert storm ends",
            report(minutes: StormFixture.minutes(from: now, wet: 0..<10, chance: 0.35), chance: 0.35),
            after: storm([.alert]),
            []
        ),
        StormTriggerCase("an advisory does not hold an alert storm", report(alerts: [StormFixture.alert("a", severity: "moderate")]), after: storm([.alert]), []),
    ]

    @Test(arguments: triggers)
    func trigger(_ trigger: StormTriggerCase) {
        let evaluation = StormRules().evaluate(report: trigger.report, at: now, previous: trigger.previous)
        #expect(evaluation.state.reasons == trigger.expected)
        #expect(evaluation.state.isActive == !trigger.expected.isEmpty)
        #expect(evaluation.lastSignal == (trigger.expected.isEmpty ? nil : now))
    }

    @Test func alertsMostSevereFirstWithTextUntouched() {
        let shouting = StormFixture.alert("e1", severity: "extreme", summary: "TORNADO WARNING in effect until 3:15 PM CST... take cover NOW!")
        let alerts = [
            StormFixture.alert("m1", severity: "minor"),
            shouting,
            StormFixture.alert("u1", severity: "unknown"),
            StormFixture.alert("s1", severity: "severe"),
            StormFixture.alert("e2", severity: "extreme"),
            StormFixture.alert("o1", severity: "moderate"),
            StormFixture.alert("x1", severity: "notAThing"),
            StormFixture.alert("s2", severity: "severe"),
        ]
        let state = StormRules().evaluate(report: report(alerts: alerts), at: now).state
        #expect(state.alerts.map(\.id) == ["e1", "e2", "s1", "s2", "o1", "m1", "u1", "x1"])
        #expect(state.alerts.first == shouting)
        #expect(Set(state.alerts) == Set(alerts))
    }

    @Test func swingsAroundHalfEveryRefreshNeverFlap() {
        let rules = StormRules()
        var evaluation = StormEvaluation.calm
        var history: [Bool] = []
        for step in 0..<18 {
            let time = now.addingTimeInterval(TimeInterval(step) * 10 * minute)
            let chance = step.isMultiple(of: 2) ? 0.48 : 0.52
            let swinging = StormFixture.report(at: time, chance: chance)
            evaluation = rules.evaluate(report: swinging, at: time, previous: evaluation)
            history.append(evaluation.state.isActive)
        }
        #expect(history == [false] + Array(repeating: true, count: 17))
        #expect(evaluation.state.reasons == [.hourlyChance])
    }

    @Test func entryNeedsHalfButActiveHoldsDownToThirtyPercent() {
        let rules = StormRules()
        let calm = rules.evaluate(report: report(chance: 0.45), at: now)
        #expect(!calm.state.isActive)

        let on = rules.evaluate(report: report(chance: 0.5), at: now)
        let held = rules.evaluate(report: report(chance: 0.3), at: now.addingTimeInterval(10 * minute), previous: on)
        #expect(held.state.reasons == [.hourlyChance])
        #expect(held.lastSignal == now.addingTimeInterval(10 * minute))

        let minuteOn = rules.evaluate(report: report(minutes: StormFixture.minutes(from: now, wet: 0..<5, chance: 0.6)), at: now)
        let minuteHeld = rules.evaluate(
            report: report(minutes: StormFixture.minutes(from: now, wet: 0..<5, chance: 0.35)),
            at: now,
            previous: minuteOn
        )
        #expect(minuteHeld.state.reasons == [.minutePrecipitation])
    }

    @Test func exitWaitsTwentyMinutesAfterTheLastSignal() {
        let rules = StormRules()
        var evaluation = rules.evaluate(report: report(alerts: [StormFixture.alert("a")], chance: 0.6), at: now)
        #expect(evaluation.state.reasons == [.alert, .hourlyChance])

        var activeMinutes: [Int] = []
        for step in 1...30 {
            let time = now.addingTimeInterval(TimeInterval(step) * minute)
            evaluation = rules.evaluate(report: StormFixture.report(at: time, chance: 0.29), at: time, previous: evaluation)
            if evaluation.state.isActive {
                activeMinutes.append(step)
                #expect(evaluation.state.reasons == [.alert, .hourlyChance])
                #expect(evaluation.state.alerts.isEmpty)
                #expect(evaluation.lastSignal == now)
            }
        }
        #expect(activeMinutes == Array(1...19))
        #expect(evaluation == .calm)
    }

    @Test func aSignalDuringTheHoldRestartsIt() {
        let rules = StormRules()
        let on = rules.evaluate(report: report(alerts: [StormFixture.alert("a")]), at: now)
        let holding = rules.evaluate(report: report(), at: now.addingTimeInterval(15 * minute), previous: on)
        let again = rules.evaluate(report: report(chance: 0.5), at: now.addingTimeInterval(16 * minute), previous: holding)
        #expect(again.state.reasons == [.hourlyChance])
        let stillOn = rules.evaluate(report: report(), at: now.addingTimeInterval(35 * minute), previous: again)
        #expect(stillOn.state.isActive)
        let off = rules.evaluate(report: report(), at: now.addingTimeInterval(36 * minute), previous: again)
        #expect(off == .calm)
    }

    @Test func aClockThatWentBackHoldsNoLongerThanTheHold() {
        let rules = StormRules()
        let future = StormEvaluation(
            state: StormState(isActive: true, reasons: [.alert], alerts: [StormFixture.alert("a")]),
            lastSignal: now.addingTimeInterval(3 * hour)
        )
        let held = rules.evaluate(report: report(), at: now, previous: future)
        #expect(held.state.isActive)
        #expect(held.lastSignal == now)
        #expect(rules.evaluate(report: report(), at: now.addingTimeInterval(20 * minute), previous: held) == .calm)
    }

    @Test func anOfflineReportStopsHoldingStormModeAfterAnHour() {
        let rules = StormRules()
        let offline = report(alerts: [StormFixture.alert("a")], minutes: StormFixture.minutes(from: now, wet: 0..<60), chance: 0.9)
        var evaluation = StormEvaluation.calm
        var firstCalm: Date?
        for step in 0...(2 * 60) {
            let time = now.addingTimeInterval(TimeInterval(step) * minute)
            evaluation = rules.evaluate(report: offline, at: time, previous: evaluation)
            if !evaluation.state.isActive, firstCalm == nil { firstCalm = time }
        }
        #expect(firstCalm == now.addingTimeInterval(80 * minute))
        #expect(evaluation == .calm)
    }

    @Test func noReportEndsStormModeAfterTheHold() {
        let rules = StormRules()
        let on = rules.evaluate(report: report(alerts: [StormFixture.alert("a")]), at: now)
        #expect(rules.evaluate(report: nil, at: now.addingTimeInterval(19 * minute), previous: on).state.isActive)
        #expect(rules.evaluate(report: nil, at: now.addingTimeInterval(20 * minute), previous: on) == .calm)
    }

    @Test func everyAlertIsListedWhileStormModeIsOnForAnyReason() {
        let rules = StormRules()
        let advisory = StormFixture.alert("heat", severity: "minor", summary: "Heat Advisory")
        let warning = StormFixture.alert("flood", severity: "severe", summary: "Flood Warning")
        let wet = StormFixture.minutes(from: now, wet: 0..<10)

        let advisoryOnly = rules.evaluate(report: report(alerts: [advisory]), at: now)
        #expect(advisoryOnly == .calm)

        let raining = rules.evaluate(report: report(alerts: [advisory], minutes: wet), at: now)
        #expect(raining.state.reasons == [.minutePrecipitation])
        #expect(raining.state.alerts == [advisory])

        let both = rules.evaluate(report: report(alerts: [advisory, warning], minutes: wet), at: now)
        #expect(both.state.reasons == [.alert, .minutePrecipitation])
        #expect(both.state.alerts == [warning, advisory])

        let holding = rules.evaluate(report: report(alerts: [advisory]), at: now.addingTimeInterval(5 * minute), previous: raining)
        #expect(holding.state.reasons == [.minutePrecipitation])
        #expect(holding.state.alerts == [advisory])
    }

    @Test func alertSeveritiesAreConfigurable() {
        let rules = StormRules(alertSeverities: ["extreme", "severe", "moderate"])
        let wind = StormFixture.alert("wind", severity: "moderate", summary: "Wind Advisory")
        #expect(rules.evaluate(report: report(alerts: [wind]), at: now).state.reasons == [.alert])
        #expect(rules.triggers(wind))
        #expect(!StormRules().triggers(wind))
    }
}
