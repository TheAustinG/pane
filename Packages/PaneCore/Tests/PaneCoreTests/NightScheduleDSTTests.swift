import Foundation
import Testing
@testable import PaneCore

private let cal = NightTestClock.chicago
private let at = NightTestClock.instant

/// America/Chicago: 2026-03-08 skips 2:00 to 3:00 (CST to CDT) and 2026-11-01 repeats 1:00 to 2:00
/// (CDT to CST).
@Suite("NightSchedule daylight saving")
struct NightScheduleDSTTests {
    @Test func springForwardStandardScheduleCrossesTheGap() {
        let schedule = NightSchedule.standard
        let start = at("2026-03-07T23:00:00-06:00")
        let end = at("2026-03-08T06:30:00-05:00")
        #expect(schedule.isActive(at: at("2026-03-08T01:59:00-06:00"), calendar: cal))
        #expect(schedule.isActive(at: at("2026-03-08T03:00:00-05:00"), calendar: cal))
        #expect(schedule.isActive(at: at("2026-03-08T06:29:00-05:00"), calendar: cal))
        #expect(!schedule.isActive(at: end, calendar: cal))
        #expect(schedule.nextChange(after: at("2026-03-07T12:00:00-06:00"), calendar: cal) == start)
        #expect(schedule.nextChange(after: start, calendar: cal) == end)
    }

    @Test func springForwardStartInsideTheGapMovesToThreeAM() {
        let schedule = NightSchedule.window(2, 30, to: 6)
        let start = at("2026-03-08T03:00:00-05:00")
        #expect(schedule.nextChange(after: at("2026-03-08T00:00:00-06:00"), calendar: cal) == start)
        #expect(!schedule.isActive(at: at("2026-03-08T01:59:00-06:00"), calendar: cal))
        #expect(schedule.isActive(at: start, calendar: cal))
        #expect(schedule.nextChange(after: start, calendar: cal) == at("2026-03-08T06:00:00-05:00"))
    }

    @Test func springForwardEndInsideTheGapMovesToThreeAM() {
        let schedule = NightSchedule.window(22, to: 2, 30)
        let end = at("2026-03-08T03:00:00-05:00")
        #expect(schedule.isActive(at: at("2026-03-08T01:59:00-06:00"), calendar: cal))
        #expect(schedule.nextChange(after: at("2026-03-08T00:00:00-06:00"), calendar: cal) == end)
        #expect(!schedule.isActive(at: end, calendar: cal))
    }

    @Test func springForwardWindowEntirelyInsideTheGapIsEmpty() {
        let schedule = NightSchedule.window(2, 15, to: 2, 45)
        let day = at("2026-03-08T00:00:00-06:00")
        #expect(!schedule.isActive(at: at("2026-03-08T03:00:00-05:00"), calendar: cal))
        #expect(!schedule.isActive(at: at("2026-03-08T03:10:00-05:00"), calendar: cal))
        #expect(schedule.nextChange(after: day, calendar: cal) == at("2026-03-09T02:15:00-05:00"))
    }

    @Test func fallBackStandardScheduleCoversTheRepeatedHour() {
        let schedule = NightSchedule.standard
        let start = at("2026-10-31T23:00:00-05:00")
        let end = at("2026-11-01T06:30:00-06:00")
        #expect(schedule.isActive(at: at("2026-11-01T01:30:00-05:00"), calendar: cal))
        #expect(schedule.isActive(at: at("2026-11-01T01:30:00-06:00"), calendar: cal))
        #expect(schedule.isActive(at: at("2026-11-01T06:29:00-06:00"), calendar: cal))
        #expect(!schedule.isActive(at: end, calendar: cal))
        #expect(schedule.nextChange(after: at("2026-10-31T12:00:00-05:00"), calendar: cal) == start)
        #expect(schedule.nextChange(after: start, calendar: cal) == end)
    }

    @Test func fallBackEndInsideRepeatedHourHappensOnceAtFirstOccurrence() {
        let schedule = NightSchedule.window(22, to: 1, 30)
        let end = at("2026-11-01T01:30:00-05:00")
        #expect(schedule.isActive(at: at("2026-11-01T01:29:00-05:00"), calendar: cal))
        #expect(!schedule.isActive(at: end, calendar: cal))
        #expect(!schedule.isActive(at: at("2026-11-01T01:30:00-06:00"), calendar: cal))
        #expect(schedule.nextChange(after: at("2026-11-01T00:00:00-05:00"), calendar: cal) == end)
        #expect(schedule.nextChange(after: end, calendar: cal) == at("2026-11-01T22:00:00-06:00"))
    }

    @Test func fallBackStartInsideRepeatedHourHappensOnceAtFirstOccurrence() {
        let schedule = NightSchedule.window(1, 30, to: 6)
        let start = at("2026-11-01T01:30:00-05:00")
        #expect(!schedule.isActive(at: at("2026-11-01T01:29:00-05:00"), calendar: cal))
        #expect(schedule.isActive(at: start, calendar: cal))
        #expect(schedule.isActive(at: at("2026-11-01T01:30:00-06:00"), calendar: cal))
        #expect(schedule.nextChange(after: at("2026-11-01T00:00:00-05:00"), calendar: cal) == start)
        #expect(schedule.nextChange(after: start, calendar: cal) == at("2026-11-01T06:00:00-06:00"))
    }

    @Test func nextChangeNeverReturnsADuplicateInTheRepeatedHour() {
        let schedule = NightSchedule.window(22, to: 1, 30)
        let afterFirst = at("2026-11-01T01:30:00-05:00")
        let next = schedule.nextChange(after: afterFirst, calendar: cal)
        #expect(next != at("2026-11-01T01:30:00-06:00"))
    }
}
