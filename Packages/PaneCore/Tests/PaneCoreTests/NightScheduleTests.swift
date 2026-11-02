import Foundation
import Testing
@testable import PaneCore

private let cal = NightTestClock.chicago
private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    NightTestClock.local(y, m, d, h, min)
}

@Suite("NightSchedule basics")
struct NightScheduleBasicsTests {
    @Test func crossMidnightWindow() {
        let schedule = NightSchedule.standard
        #expect(schedule.isActive(at: local(2026, 6, 10, 23, 30), calendar: cal))
        #expect(schedule.isActive(at: local(2026, 6, 11, 0, 0), calendar: cal))
        #expect(schedule.isActive(at: local(2026, 6, 11, 3, 15), calendar: cal))
        #expect(schedule.isActive(at: local(2026, 6, 11, 6, 29), calendar: cal))
        #expect(!schedule.isActive(at: local(2026, 6, 11, 6, 31), calendar: cal))
        #expect(!schedule.isActive(at: local(2026, 6, 11, 12, 0), calendar: cal))
        #expect(!schedule.isActive(at: local(2026, 6, 11, 22, 59), calendar: cal))
    }

    @Test func sameDayWindow() {
        let schedule = NightSchedule.window(13, to: 15, 30)
        #expect(!schedule.isActive(at: local(2026, 6, 10, 12, 59), calendar: cal))
        #expect(schedule.isActive(at: local(2026, 6, 10, 14, 0), calendar: cal))
        #expect(!schedule.isActive(at: local(2026, 6, 10, 15, 30), calendar: cal))
        #expect(!schedule.isActive(at: local(2026, 6, 10, 23, 0), calendar: cal))
        #expect(!schedule.isActive(at: local(2026, 6, 11, 1, 0), calendar: cal))
    }

    @Test func boundariesAreStartInclusiveEndExclusive() {
        let schedule = NightSchedule.standard
        #expect(!schedule.isActive(at: local(2026, 6, 10, 22, 59), calendar: cal))
        #expect(schedule.isActive(at: local(2026, 6, 10, 23, 0), calendar: cal))
        #expect(schedule.isActive(at: local(2026, 6, 11, 6, 29), calendar: cal))
        #expect(!schedule.isActive(at: local(2026, 6, 11, 6, 30), calendar: cal))
    }

    @Test func disabledIsNeverActive() {
        var schedule = NightSchedule.standard
        schedule.isEnabled = false
        #expect(!schedule.isActive(at: local(2026, 6, 11, 2, 0), calendar: cal))
        #expect(schedule.nextChange(after: local(2026, 6, 11, 2, 0), calendar: cal) == nil)
    }

    @Test func equalStartAndEndIsNeverActive() {
        let schedule = NightSchedule.window(22, to: 22)
        #expect(!schedule.isActive(at: local(2026, 6, 10, 22, 0), calendar: cal))
        #expect(!schedule.isActive(at: local(2026, 6, 10, 23, 0), calendar: cal))
        #expect(!schedule.isActive(at: local(2026, 6, 11, 12, 0), calendar: cal))
        #expect(schedule.nextChange(after: local(2026, 6, 10, 12, 0), calendar: cal) == nil)
    }

    @Test func nextChangeWalksOnAndOff() {
        let schedule = NightSchedule.standard
        var date = local(2026, 6, 10, 12, 0)
        var seen: [Date] = []
        for _ in 0..<4 {
            let next = try! #require(schedule.nextChange(after: date, calendar: cal))
            seen.append(next)
            date = next
        }
        #expect(seen == [
            local(2026, 6, 10, 23, 0),
            local(2026, 6, 11, 6, 30),
            local(2026, 6, 11, 23, 0),
            local(2026, 6, 12, 6, 30),
        ])
    }

    @Test func nextChangeIsStrictlyAfter() {
        let schedule = NightSchedule.standard
        #expect(schedule.nextChange(after: local(2026, 6, 10, 23, 0), calendar: cal) == local(2026, 6, 11, 6, 30))
        #expect(schedule.nextChange(after: local(2026, 6, 11, 6, 30), calendar: cal) == local(2026, 6, 11, 23, 0))
    }

    @Test func nextChangeFromInsideWindow() {
        #expect(NightSchedule.standard.nextChange(after: local(2026, 6, 11, 1, 0), calendar: cal) == local(2026, 6, 11, 6, 30))
    }

    @Test func nextChangeForSameDayWindow() {
        let schedule = NightSchedule.window(13, to: 15)
        #expect(schedule.nextChange(after: local(2026, 6, 10, 16, 0), calendar: cal) == local(2026, 6, 11, 13, 0))
        #expect(schedule.nextChange(after: local(2026, 6, 10, 14, 0), calendar: cal) == local(2026, 6, 10, 15, 0))
    }

    @Test func nextStartAndEnd() {
        let schedule = NightSchedule.standard
        let noon = local(2026, 6, 10, 12, 0)
        #expect(schedule.nextStart(after: noon, calendar: cal) == local(2026, 6, 10, 23, 0))
        #expect(schedule.nextEnd(after: noon, calendar: cal) == local(2026, 6, 11, 6, 30))
        let inside = local(2026, 6, 11, 2, 0)
        #expect(schedule.nextEnd(after: inside, calendar: cal) == local(2026, 6, 11, 6, 30))
        #expect(schedule.nextStart(after: inside, calendar: cal) == local(2026, 6, 11, 23, 0))
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(NightSchedule.standard)
        #expect(try JSONDecoder().decode(NightSchedule.self, from: data) == .standard)
    }
}
