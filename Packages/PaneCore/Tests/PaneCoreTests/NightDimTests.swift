import Foundation
import Testing
@testable import PaneCore

private let cal = NightTestClock.chicago
private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    NightTestClock.local(y, m, d, h, min)
}

@Suite("NightDim")
struct NightDimTests {
    private let schedule = NightSchedule.standard
    private let night = local(2026, 11, 2, 1, 0)
    private let day = local(2026, 11, 2, 14, 0)

    @Test func noOverrideFollowsTheSchedule() {
        #expect(NightDim.isDimmed(at: night, schedule: schedule, override: .none, calendar: cal))
        #expect(!NightDim.isDimmed(at: day, schedule: schedule, override: .none, calendar: cal))
    }

    @Test func unexpiredOverrideWins() {
        let later = day.addingTimeInterval(3600)
        #expect(NightDim.isDimmed(at: day, schedule: schedule, override: .dimmed(until: later), calendar: cal))
        let nightLater = night.addingTimeInterval(3600)
        #expect(!NightDim.isDimmed(at: night, schedule: schedule, override: .bright(until: nightLater), calendar: cal))
    }

    @Test func overrideWinsOverADisabledSchedule() {
        var off = schedule
        off.isEnabled = false
        let later = day.addingTimeInterval(3600)
        #expect(NightDim.isDimmed(at: day, schedule: off, override: .dimmed(until: later), calendar: cal))
    }

    @Test func overrideExpiresExactlyAtUntil() {
        let until = day.addingTimeInterval(3600)
        #expect(NightDim.isDimmed(at: until.addingTimeInterval(-1), schedule: schedule, override: .dimmed(until: until), calendar: cal))
        #expect(!NightDim.isDimmed(at: until, schedule: schedule, override: .dimmed(until: until), calendar: cal))
    }

    @Test func expiredOverrideIsIgnored() {
        let past = night.addingTimeInterval(-60)
        #expect(NightDim.isDimmed(at: night, schedule: schedule, override: .bright(until: past), calendar: cal))
        #expect(!NightDim.isDimmed(at: day, schedule: schedule, override: .dimmed(until: day.addingTimeInterval(-60)), calendar: cal))
    }

    @Test func toggleBrightAtDaytimeDimsUntilTheNextEnd() {
        let result = NightDim.toggled(at: day, schedule: schedule, current: .none, calendar: cal)
        #expect(result == .dimmed(until: local(2026, 11, 3, 6, 30)))
    }

    @Test func toggleBrightDuringScheduleWithBrightOverrideDimsUntilTheWindowEnds() {
        let current = NightDimOverride.bright(until: local(2026, 11, 2, 6, 30))
        let result = NightDim.toggled(at: night, schedule: schedule, current: current, calendar: cal)
        #expect(result == .dimmed(until: local(2026, 11, 2, 6, 30)))
    }

    @Test func toggleDimmedBySchedulePicksBrightUntilTheWindowEnds() {
        let result = NightDim.toggled(at: night, schedule: schedule, current: .none, calendar: cal)
        #expect(result == .bright(until: local(2026, 11, 2, 6, 30)))
    }

    @Test func toggleDimmedByOverrideOutsideTheWindowPicksBrightUntilTheNextStart() {
        let current = NightDimOverride.dimmed(until: local(2026, 11, 3, 6, 30))
        let result = NightDim.toggled(at: day, schedule: schedule, current: current, calendar: cal)
        #expect(result == .bright(until: local(2026, 11, 2, 23, 0)))
    }

    @Test func toggleTwiceReturnsToTheScheduleBehaviour() {
        let first = NightDim.toggled(at: night, schedule: schedule, current: .none, calendar: cal)
        #expect(!NightDim.isDimmed(at: night, schedule: schedule, override: first, calendar: cal))
        let second = NightDim.toggled(at: night, schedule: schedule, current: first, calendar: cal)
        #expect(NightDim.isDimmed(at: night, schedule: schedule, override: second, calendar: cal))
    }

    @Test func disabledScheduleDimsUntilTheNextEndTime() {
        var off = schedule
        off.isEnabled = false
        let result = NightDim.toggled(at: day, schedule: off, current: .none, calendar: cal)
        #expect(result == .dimmed(until: local(2026, 11, 3, 6, 30)))
        let early = local(2026, 11, 2, 5, 0)
        #expect(NightDim.toggled(at: early, schedule: off, current: .none, calendar: cal) == .dimmed(until: local(2026, 11, 2, 6, 30)))
    }

    @Test func disabledScheduleBrightensUntilTheNextEndTime() {
        var off = schedule
        off.isEnabled = false
        let current = NightDimOverride.dimmed(until: local(2026, 11, 3, 6, 30))
        let result = NightDim.toggled(at: day, schedule: off, current: current, calendar: cal)
        #expect(result == .bright(until: local(2026, 11, 3, 6, 30)))
    }

    @Test func equalStartAndEndFallsBackToTheNextEndTime() {
        let flat = NightSchedule.window(22, to: 22)
        let result = NightDim.toggled(at: day, schedule: flat, current: .none, calendar: cal)
        #expect(result == .dimmed(until: local(2026, 11, 2, 22, 0)))
    }

    @Test func overrideRoundTripsThroughJSON() throws {
        let value = NightDimOverride.dimmed(until: local(2026, 11, 2, 6, 30))
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(NightDimOverride.self, from: data) == value)
    }
}
