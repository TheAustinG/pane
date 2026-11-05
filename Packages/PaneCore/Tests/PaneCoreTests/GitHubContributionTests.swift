import Foundation
import Testing
@testable import PaneCore

private func day(_ text: String) -> CalendarDay {
    CalendarDay(string: text)!
}

/// A calendar with `counts` on the named days, every day from `from` through `through` present.
private func contributions(_ counts: [String: Int], from: String, through: String) -> ContributionCalendar {
    var days: [ContributionDay] = []
    var cursor = day(from)
    while cursor <= day(through) {
        let count = counts[cursor.description] ?? 0
        days.append(ContributionDay(day: cursor, count: count, level: min(count, 4)))
        cursor = cursor.adding(days: 1)
    }
    return ContributionCalendar(days: days)
}

private func summary(_ calendar: ContributionCalendar, at date: Date, weeks: Int = 26) -> ContributionSummary {
    ContributionSummary.make(calendar: calendar, today: CalendarDay(date: date, timeZone: WeatherFixture.calendar.timeZone), weeks: weeks)
}

private let chicago = WeatherFixture.calendar

private func chicagoDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    chicago.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

@Suite("GitHub contributions")
struct GitHubContributionTests {
    @Test func dayStepping() {
        #expect(day("2026-02-28").adding(days: 1) == day("2026-03-01"))
        #expect(day("2028-02-28").adding(days: 1) == day("2028-02-29"))
        #expect(day("2026-01-01").adding(days: -1) == day("2025-12-31"))
        #expect(day("2026-03-08").adding(days: 1) == day("2026-03-09"))
        #expect(day("2026-11-01").adding(days: -1) == day("2026-10-31"))
        #expect(day("2026-11-03").adding(days: -365) == day("2025-11-03"))
        #expect(day("2026-11-01").weekday == 1)
        #expect(day("2026-11-03").weekday == 3)
        #expect(day("2026-11-07").weekday == 7)
    }

    @Test func todayIsTheChicagoDayEitherSideOfMidnight() {
        let calendar = contributions(["2026-11-02": 4, "2026-11-03": 2], from: "2026-10-01", through: "2026-11-03")
        let beforeMidnight = summary(calendar, at: chicagoDate(2026, 11, 3, 23, 59, 59))
        #expect(beforeMidnight.todayCount == 2)
        #expect(beforeMidnight.streak == 2)

        // Two seconds later it is the 4th in Chicago with nothing yet, and the streak holds.
        let afterMidnight = summary(calendar, at: chicagoDate(2026, 11, 4, 0, 0, 1))
        #expect(afterMidnight.todayCount == 0)
        #expect(afterMidnight.streak == 2)

        let utcSameInstant = CalendarDay(date: chicagoDate(2026, 11, 3, 23, 30), timeZone: TimeZone(identifier: "UTC")!)
        #expect(utcSameInstant == day("2026-11-04"))
    }

    @Test func streakCountsBackFromToday() {
        let calendar = contributions(
            ["2026-10-28": 1, "2026-10-30": 3, "2026-10-31": 1, "2026-11-01": 5, "2026-11-02": 2, "2026-11-03": 7],
            from: "2026-10-01",
            through: "2026-11-03"
        )
        let result = summary(calendar, at: chicagoDate(2026, 11, 3, 12))
        #expect(result.streak == 5)
        #expect(result.todayCount == 7)
    }

    @Test func zeroTodayDoesNotBreakTheStreak() {
        let calendar = contributions(["2026-11-01": 1, "2026-11-02": 2], from: "2026-10-01", through: "2026-11-03")
        let result = summary(calendar, at: chicagoDate(2026, 11, 3, 9))
        #expect(result.todayCount == 0)
        #expect(result.streak == 2)
    }

    @Test func todayMissingFromTheCalendarCountsAsZero() {
        let calendar = contributions(["2026-11-01": 1, "2026-11-02": 2], from: "2026-10-01", through: "2026-11-02")
        let result = summary(calendar, at: chicagoDate(2026, 11, 3, 0, 5))
        #expect(result.todayCount == 0)
        #expect(result.streak == 2)
    }

    @Test func aZeroYesterdayAndTodayIsNoStreak() {
        let calendar = contributions(["2026-11-01": 4], from: "2026-10-01", through: "2026-11-03")
        #expect(summary(calendar, at: chicagoDate(2026, 11, 3, 12)).streak == 0)
        #expect(summary(ContributionCalendar(days: []), at: chicagoDate(2026, 11, 3, 12)) == ContributionSummary(
            streak: 0,
            todayCount: 0,
            levels: Array(repeating: 0, count: 26 * 7 - 4) + [-1, -1, -1, -1]
        ))
    }

    @Test func streakCrossesTheSpringClockChange() {
        // Chicago skips 02:00 to 03:00 on 2026-03-08; that day is 23 hours long.
        let counts = ["2026-03-06": 1, "2026-03-07": 1, "2026-03-08": 1, "2026-03-09": 1, "2026-03-10": 1]
        let calendar = contributions(counts, from: "2026-02-01", through: "2026-03-10")
        #expect(summary(calendar, at: chicagoDate(2026, 3, 10, 0, 30)).streak == 5)
        #expect(summary(calendar, at: chicagoDate(2026, 3, 10, 23, 59)).streak == 5)
        #expect(CalendarDay(date: chicagoDate(2026, 3, 8, 1, 59), timeZone: chicago.timeZone) == day("2026-03-08"))
        #expect(CalendarDay(date: chicagoDate(2026, 3, 8, 3, 1), timeZone: chicago.timeZone) == day("2026-03-08"))
        #expect(CalendarDay(date: chicagoDate(2026, 3, 9, 0, 0, 1), timeZone: chicago.timeZone) == day("2026-03-09"))
        #expect(CalendarDay(date: chicagoDate(2026, 3, 8, 23, 59, 59), timeZone: chicago.timeZone) == day("2026-03-08"))
    }

    @Test func streakCrossesTheAutumnClockChange() {
        // Chicago repeats 01:00 to 02:00 on 2026-11-01; that day is 25 hours long.
        let counts = ["2026-10-30": 2, "2026-10-31": 2, "2026-11-01": 2, "2026-11-02": 2, "2026-11-03": 2]
        let calendar = contributions(counts, from: "2026-10-01", through: "2026-11-03")
        #expect(summary(calendar, at: chicagoDate(2026, 11, 3, 0, 1)).streak == 5)
        let firstOneThirty = chicago.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30))!
        let secondOneThirty = firstOneThirty.addingTimeInterval(3600)
        #expect(CalendarDay(date: firstOneThirty, timeZone: chicago.timeZone) == day("2026-11-01"))
        #expect(CalendarDay(date: secondOneThirty, timeZone: chicago.timeZone) == day("2026-11-01"))
        #expect(CalendarDay(date: chicagoDate(2026, 11, 1, 23, 59, 59), timeZone: chicago.timeZone) == day("2026-11-01"))
        #expect(CalendarDay(date: chicagoDate(2026, 11, 2, 0, 0, 1), timeZone: chicago.timeZone) == day("2026-11-02"))
    }

    @Test func streakCrossesTheYear() {
        let counts = ["2025-12-29": 1, "2025-12-30": 1, "2025-12-31": 1, "2026-01-01": 1, "2026-01-02": 1]
        let calendar = contributions(counts, from: "2025-12-01", through: "2026-01-02")
        let result = summary(calendar, at: chicagoDate(2026, 1, 2, 18), weeks: 2)
        #expect(result.streak == 5)
        // 2025-12-21 (Sunday) through 2026-01-03 (Saturday); today is Friday the 2nd.
        #expect(result.levels == [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, -1])
    }

    @Test func gridRunsSundayToSaturdayWithTheFutureBlank() {
        let calendar = contributions(
            ["2026-10-25": 1, "2026-10-31": 2, "2026-11-01": 3, "2026-11-02": 4, "2026-11-03": 9],
            from: "2026-10-01",
            through: "2026-11-03"
        )
        let result = summary(calendar, at: chicagoDate(2026, 11, 3, 12), weeks: 3)
        #expect(result.levels.count == 21)
        #expect(Array(result.levels[0..<7]) == [0, 0, 0, 0, 0, 0, 0])
        #expect(Array(result.levels[7..<14]) == [1, 0, 0, 0, 0, 0, 2])
        #expect(Array(result.levels[14..<21]) == [3, 4, 4, -1, -1, -1, -1])
    }

    @Test func gridEdgesOfTheWeek() {
        let calendar = contributions(["2026-11-01": 1, "2026-11-07": 2], from: "2026-10-01", through: "2026-11-07")
        let sunday = summary(calendar, at: chicagoDate(2026, 11, 1, 8), weeks: 1)
        #expect(sunday.levels == [1, -1, -1, -1, -1, -1, -1])
        let saturday = summary(calendar, at: chicagoDate(2026, 11, 7, 8), weeks: 1)
        #expect(saturday.levels == [1, 0, 0, 0, 0, 0, 2])
        #expect(summary(calendar, at: chicagoDate(2026, 11, 7, 8), weeks: 0).levels.isEmpty)
    }

    @Test func daysBeforeTheCalendarStartsAreZero() {
        let calendar = contributions(["2026-10-28": 3], from: "2026-10-28", through: "2026-11-03")
        let result = summary(calendar, at: chicagoDate(2026, 11, 3, 12), weeks: 2)
        #expect(result.levels == [0, 0, 0, 3, 0, 0, 0, 0, 0, 0, -1, -1, -1, -1])
    }

    @Test func recordedCalendarMatchesGitHub() throws {
        let viewer = try GitHubClient.parseViewer(CodeSample.data("github-viewer"), now: CodeSample.start)
        let result = summary(viewer.calendar, at: chicagoDate(2026, 11, 3, 21))
        #expect(result.todayCount == 7)
        #expect(result.streak == 5)
        #expect(result.levels.count == 26 * 7)
        #expect(Array(result.levels.suffix(7)) == [1, 2, 1, -1, -1, -1, -1])
        let firstColumn = day("2026-11-01").adding(days: -7 * 25)
        #expect(firstColumn == day("2026-05-10"))
        let byDay = Dictionary(uniqueKeysWithValues: viewer.calendar.days.map { ($0.day, $0.level) })
        for index in 0..<(25 * 7 + 3) {
            #expect(result.levels[index] == byDay[firstColumn.adding(days: index)] ?? 0)
        }
    }

    @MainActor
    @Test func controllerCountsTodayInItsCalendarsTimeZone() {
        let calendar = contributions(["2026-11-03": 2, "2026-11-04": 6], from: "2026-10-01", through: "2026-11-04")
        let snapshot = GitHubSnapshot(login: "sample", calendar: calendar, latestCommit: nil, fetchedAt: CodeSample.start)
        let controller = CodeController.preview(github: snapshot, containers: [], runs: [])
        let instant = chicagoDate(2026, 11, 3, 22)
        controller.now = { instant }
        controller.calendar = chicago
        #expect(controller.contributionSummary(weeks: 1)?.todayCount == 2)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        controller.calendar = utc
        #expect(controller.contributionSummary(weeks: 1)?.todayCount == 6)
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = chicago.timeZone
        controller.calendar = buddhist
        #expect(controller.contributionSummary(weeks: 1)?.todayCount == 2)
    }
}
