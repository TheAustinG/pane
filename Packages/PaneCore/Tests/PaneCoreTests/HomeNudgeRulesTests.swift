import Foundation
import Testing
@testable import PaneCore

private let loft = "sensor.loft_humidity"
private let studio = "sensor.studio_humidity"
private let lock = "lock.side_gate"
private let pantry = "light.pantry"
private let gazebo = "light.gazebo"
private let nook = "switch.reading_nook"
private let robin = "person.robin"
private let kit = "person.kit"
private let tv = "media_player.loft_tv"

private func dry(_ ids: String...) -> HomeNudge { HomeNudge(kind: .dryAir, entityIDs: ids) }
private func humid(_ ids: String...) -> HomeNudge { HomeNudge(kind: .humidAir, entityIDs: ids) }
private func lights(_ ids: String...) -> HomeNudge { HomeNudge(kind: .lightsOnAway, entityIDs: ids) }
private let door = HomeNudge(kind: .doorUnlockedLate, entityIDs: [lock])
private let lateTV = HomeNudge(kind: .bedroomTVLate, entityIDs: [tv])
private let away = [robin: "not_home", kit: "not_home"]

struct NudgeCase: Sendable, CustomTestStringConvertible {
    let name: String
    let states: [String: String]
    let hour: Int
    let minute: Int
    let selection: HomeSelection
    let disabled: Set<HomeNudgeKind>
    let previous: [HomeNudgeKind]
    let expected: [HomeNudge]

    init(
        _ name: String,
        _ states: [String: String] = [:],
        at time: (hour: Int, minute: Int) = (14, 0),
        selection: (inout HomeSelection) -> Void = { _ in },
        disabled: Set<HomeNudgeKind> = [],
        raised previous: [HomeNudgeKind] = [],
        _ expected: [HomeNudge]
    ) {
        self.name = name
        self.states = states
        hour = time.hour
        minute = time.minute
        var chosen = HomeSample.selection
        selection(&chosen)
        self.selection = chosen
        self.disabled = disabled
        self.previous = previous
        self.expected = expected
    }

    var testDescription: String { name }

    /// The sample home: humidity 45 and 50, lock locked, lights off, both people home, TV off.
    var entities: [String: HAEntity] {
        var entities = HomeSample.byID
        for (id, state) in states {
            entities[id] = (entities[id] ?? HomeSample.entity(id, state)).with(state: state)
        }
        return entities
    }
}

private extension HAEntity {
    func with(state: String) -> HAEntity {
        var copy = self
        copy.state = state
        return copy
    }
}

/// Thresholds under test: dry below 35 percent, held until 37; humid above 60, held until 58; door
/// from 22:00 to 06:00; TV from 00:00 to 05:00, Chicago time.
@Suite("Home nudge rules")
struct HomeNudgeRulesTests {
    static let cases: [NudgeCase] = [
        NudgeCase("a calm home", [:], []),
        NudgeCase("dry at 34.9", [loft: "34.9"], [dry(loft)]),
        NudgeCase("35 is not dry", [loft: "35"], []),
        NudgeCase("the lowest of two sensors is dry", [studio: "30"], [dry(studio)]),
        NudgeCase("both sensors dry", [loft: "30", studio: "20"], [dry(loft, studio)]),
        NudgeCase("raised dry air holds at 36.9", [loft: "36.9"], raised: [.dryAir], [dry(loft)]),
        NudgeCase("raised dry air clears at 37", [loft: "37"], raised: [.dryAir], []),
        NudgeCase("36 is clear unless already raised", [loft: "36"], []),
        NudgeCase("an unavailable sensor is skipped", [loft: "unavailable"], []),
        NudgeCase("an unknown sensor clears raised dry air", [loft: "unknown", studio: "50"], raised: [.dryAir], []),
        NudgeCase("a reading that is not a number is skipped", [loft: "n/a"], []),
        NudgeCase("dry air turned off", [loft: "20"], disabled: [.dryAir], []),
        NudgeCase("a dry sensor that is not selected", [loft: "20"], selection: { $0.humiditySensors = [studio] }, []),
        NudgeCase("no humidity sensors selected", [loft: "20", studio: "80"], selection: { $0.humiditySensors = [] }, []),
        NudgeCase("a selected sensor missing from the states", [studio: "20"], selection: { $0.humiditySensors = ["sensor.gone", studio] }, [dry(studio)]),

        NudgeCase("humid at 60.1", [studio: "60.1"], [humid(studio)]),
        NudgeCase("60 is not humid", [studio: "60"], []),
        NudgeCase("the highest of two sensors is humid", [loft: "70"], [humid(loft)]),
        NudgeCase("raised humid air holds at 58.1", [studio: "58.1"], raised: [.humidAir], [humid(studio)]),
        NudgeCase("raised humid air clears at 58", [studio: "58"], raised: [.humidAir], []),
        NudgeCase("humid air turned off", [studio: "70"], disabled: [.humidAir], []),
        NudgeCase("an unavailable humid sensor is skipped", [studio: "unavailable"], raised: [.humidAir], []),
        NudgeCase("dry and humid in different rooms", [loft: "30", studio: "65"], [dry(loft), humid(studio)]),

        NudgeCase("unlocked at 22:00", [lock: "unlocked"], at: (22, 0), [door]),
        NudgeCase("unlocked at 21:59", [lock: "unlocked"], at: (21, 59), []),
        NudgeCase("unlocked at 05:59", [lock: "unlocked"], at: (5, 59), [door]),
        NudgeCase("unlocked at 06:00", [lock: "unlocked"], at: (6, 0), []),
        NudgeCase("unlocked in the afternoon", [lock: "unlocked"], []),
        NudgeCase("open at 02:00", [lock: "open"], at: (2, 0), [door]),
        NudgeCase("opening at 02:00", [lock: "opening"], at: (2, 0), [door]),
        NudgeCase("jammed at 23:00", [lock: "jammed"], at: (23, 0), [door]),
        NudgeCase("unlocking at 23:00", [lock: "unlocking"], at: (23, 0), [door]),
        NudgeCase("locking at 23:00", [lock: "locking"], at: (23, 0), []),
        NudgeCase("locked at 23:00", [lock: "locked"], at: (23, 0), []),
        NudgeCase("an unavailable lock at 23:00", [lock: "unavailable"], at: (23, 0), []),
        NudgeCase("an unknown lock at 23:00", [lock: "unknown"], at: (23, 0), []),
        NudgeCase("the door nudge turned off", [lock: "unlocked"], at: (23, 0), disabled: [.doorUnlockedLate], []),
        NudgeCase("no lock selected", [lock: "unlocked"], at: (23, 0), selection: { $0.lock = nil }, []),

        NudgeCase("a light on with nobody home", away.merging([pantry: "on"]) { $1 }, [lights(pantry)]),
        NudgeCase("away in a named zone counts", [robin: "Work", kit: "not_home", pantry: "on", gazebo: "on"], [lights(pantry, gazebo)]),
        NudgeCase("someone home", [kit: "not_home", pantry: "on"], []),
        NudgeCase("nobody home with the lights off", away, []),
        NudgeCase("an unavailable person is skipped", [robin: "unavailable", kit: "not_home", pantry: "on"], [lights(pantry)]),
        NudgeCase("nobody known", [robin: "unavailable", kit: "unknown", pantry: "on"], []),
        NudgeCase("no people selected", away.merging([pantry: "on"]) { $1 }, selection: { $0.people = [] }, []),
        NudgeCase("a light that is not selected", away.merging([pantry: "on"]) { $1 }, selection: { $0.lights = [gazebo] }, []),
        NudgeCase("an unavailable light is skipped", away.merging([pantry: "unavailable"]) { $1 }, []),
        NudgeCase("the lights nudge turned off", away.merging([pantry: "on"]) { $1 }, disabled: [.lightsOnAway], []),
        NudgeCase("a switch in the lights role", away.merging([nook: "on"]) { $1 }, selection: { $0.lights = [nook] }, [lights(nook)]),

        NudgeCase("TV playing at 00:00", [tv: "playing"], at: (0, 0), [lateTV]),
        NudgeCase("TV on at 04:59", [tv: "on"], at: (4, 59), [lateTV]),
        NudgeCase("TV on at 05:00", [tv: "on"], at: (5, 0), []),
        NudgeCase("TV on at 23:59", [tv: "on"], at: (23, 59), []),
        NudgeCase("TV idle at 01:00", [tv: "idle"], at: (1, 0), [lateTV]),
        NudgeCase("TV paused at 01:00", [tv: "paused"], at: (1, 0), [lateTV]),
        NudgeCase("TV standby at 01:00", [tv: "standby"], at: (1, 0), []),
        NudgeCase("TV off at 01:00", [tv: "off"], at: (1, 0), []),
        NudgeCase("TV unavailable at 01:00", [tv: "unavailable"], at: (1, 0), []),
        NudgeCase("TV unknown at 01:00", [tv: "unknown"], at: (1, 0), []),
        NudgeCase("the TV nudge turned off", [tv: "playing"], at: (1, 0), disabled: [.bedroomTVLate], []),
        NudgeCase("no TV selected", [tv: "playing"], at: (1, 0), selection: { $0.bedroomTV = nil }, []),

        NudgeCase(
            "everything at 00:30, in a stable order",
            [loft: "30", lock: "unlocked", robin: "not_home", kit: "not_home", pantry: "on", tv: "playing"],
            at: (0, 30),
            [dry(loft), door, lights(pantry), lateTV]
        ),
        NudgeCase(
            "everything turned off",
            [loft: "30", lock: "unlocked", robin: "not_home", kit: "not_home", pantry: "on", tv: "playing"],
            at: (0, 30),
            disabled: Set(HomeNudgeKind.allCases),
            []
        ),
        NudgeCase("nothing selected", [loft: "30", lock: "unlocked", tv: "playing"], at: (0, 30), selection: { $0 = .empty }, []),
    ]

    @Test(arguments: cases)
    func rule(_ testCase: NudgeCase) {
        let nudges = HomeNudgeRules.evaluate(
            entities: testCase.entities,
            selection: testCase.selection,
            preferences: HomeNudgePreferences(disabled: testCase.disabled),
            previous: testCase.previous.map { HomeNudge(kind: $0) },
            at: WeatherFixture.local(2026, 11, 2, testCase.hour, testCase.minute),
            calendar: HomeSample.calendar
        )
        #expect(nudges == testCase.expected)
    }

    @Test func thresholdsMatchTheSettingsTitles() {
        #expect(HomeNudgeRules.dryAirBelow == 35)
        #expect(HomeNudgeRules.dryAirClearsAt == 37)
        #expect(HomeNudgeRules.humidAirAbove == 60)
        #expect(HomeNudgeRules.humidAirClearsAt == 58)
        #expect(HomeNudgeRules.doorLateHours == HourWindow(from: 22, until: 6))
        #expect(HomeNudgeRules.tvLateHours == HourWindow(from: 0, until: 5))
        #expect(HomeNudgeKind.dryAir.settingsTitle.contains("35"))
        #expect(HomeNudgeKind.humidAir.settingsTitle.contains("60"))
    }

    @Test func aSensorHoveringAtTheThresholdDoesNotFlap() {
        var nudges: [HomeNudge] = []
        var raisedAt: [String] = []
        for reading in ["36", "34.8", "35.2", "34.9", "36.5", "35.1", "37", "35.5", "34.9"] {
            var entities = HomeSample.byID
            entities[loft] = HomeSample.humidity(loft, reading)
            nudges = HomeNudgeRules.evaluate(
                entities: entities,
                selection: HomeSample.selection,
                preferences: HomeNudgePreferences(),
                previous: nudges,
                at: HomeSample.start,
                calendar: HomeSample.calendar
            )
            raisedAt.append(nudges.isEmpty ? "-" : reading)
        }
        #expect(raisedAt == ["-", "34.8", "35.2", "34.9", "36.5", "35.1", "-", "-", "34.9"])
    }

    @Test func hourWindowsWrapPastMidnight() {
        let late = HourWindow(from: 22, until: 6)
        #expect((0..<24).filter(late.contains(hour:)) == [0, 1, 2, 3, 4, 5, 22, 23])
        let night = HourWindow(from: 0, until: 5)
        #expect((0..<24).filter(night.contains(hour:)) == [0, 1, 2, 3, 4])
        #expect((0..<24).filter(HourWindow(from: 8, until: 8).contains(hour:)).isEmpty)
    }

    @Test func windowsFollowLocalTimeAcrossTheDSTChange() {
        var entities = HomeSample.byID
        entities[lock] = HomeSample.entity(lock, "unlocked")
        let evaluate = { (date: Date) in
            HomeNudgeRules.evaluate(
                entities: entities,
                selection: HomeSample.selection,
                preferences: HomeNudgePreferences(),
                previous: [],
                at: date,
                calendar: HomeSample.calendar
            )
        }
        // 2026-11-01 01:30 happens twice in Chicago; 06:00 local is 12:00 UTC after the change.
        let sixLocal = WeatherFixture.local(2026, 11, 1, 6)
        #expect(evaluate(sixLocal.addingTimeInterval(-60)) == [door])
        #expect(evaluate(sixLocal) == [])
    }
}
