import Foundation
import Testing
import WeatherKit
@testable import PaneCore

private let calendar = WeatherFixture.calendar
private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { WeatherFixture.local(year, month, day, hour, minute) }

private func display(_ report: WeatherReport, at date: Date, unit: UnitTemperature = .fahrenheit) -> WeatherDisplay {
    WeatherDisplay(report: report, at: date, calendar: calendar, unit: unit)
}

private let cacheFixture = """
{
  "fetchedAt": "2026-11-02T20:05:00Z",
  "location": { "latitude": 41.88, "longitude": -87.63 },
  "current": {
    "date": "2026-11-02T20:00:00Z", "temperature": 12.2, "apparentTemperature": 11.0, "humidity": 0.55,
    "condition": "partlyCloudy", "symbolName": "cloud.sun", "isDaylight": true
  },
  "hourly": [
    { "date": "2026-11-02T20:00:00Z", "temperature": 12.2, "condition": "partlyCloudy", "symbolName": "cloud.sun", "precipitationChance": 0.0, "isDaylight": true },
    { "date": "2026-11-02T21:00:00Z", "temperature": 12.8, "condition": "partlyCloudy", "symbolName": "cloud.sun", "precipitationChance": 0.1, "isDaylight": true },
    { "date": "2026-11-02T22:00:00Z", "temperature": 11.6, "condition": "mostlyCloudy", "symbolName": "cloud", "precipitationChance": 0.24, "isDaylight": true },
    { "date": "2026-11-02T23:00:00Z", "temperature": 10.0, "condition": "cloudy", "symbolName": "cloud", "precipitationChance": 0.34, "isDaylight": false },
    { "date": "2026-11-03T00:00:00Z", "temperature": 9.4, "condition": "drizzle", "symbolName": "cloud.drizzle", "precipitationChance": 0.56, "isDaylight": false },
    { "date": "2026-11-03T01:00:00Z", "temperature": 8.9, "condition": "rain", "symbolName": "cloud.rain", "precipitationChance": 0.8, "isDaylight": false }
  ],
  "daily": [
    { "date": "2026-11-02T06:00:00Z", "high": 13.3, "low": 4.4, "condition": "partlyCloudy", "symbolName": "cloud.sun", "precipitationChance": 0.4, "sunrise": "2026-11-02T12:24:00Z", "sunset": "2026-11-02T22:44:00Z" },
    { "date": "2026-11-03T06:00:00Z", "high": 10.0, "low": 3.9, "condition": "rain", "symbolName": "cloud.rain", "precipitationChance": 0.9, "sunrise": "2026-11-03T12:25:00Z", "sunset": "2026-11-03T22:43:00Z" }
  ],
  "minutes": null,
  "alerts": []
}
"""

@Suite("Weather display mapping")
struct WeatherDisplayMappingTests {
    @Test func decodedCacheFixtureMapsToTheCards() throws {
        let report = try WeatherCache.makeDecoder().decode(WeatherReport.self, from: Data(cacheFixture.utf8))
        let shown = display(report, at: utc("2026-11-02T20:10:00Z"))

        #expect(shown.now == WeatherDisplay.Now(
            temperature: "54°", condition: "Partly Cloudy", symbolName: "cloud.sun", family: .partlyCloudy, high: "56°", low: "40°"
        ))
        #expect(shown.hours.map(\.label) == ["Now", "3 PM", "4 PM", "5 PM", "6 PM", "7 PM"])
        #expect(shown.hours.map(\.temperature) == ["54°", "55°", "53°", "50°", "49°", "48°"])
        #expect(shown.hours.map(\.precipitationPercent) == [nil, nil, 20, 30, 60, 80])
        #expect(shown.days.map(\.label) == ["Mon", "Tue"])
        #expect(shown.daylight.sunrise == "6:24 AM")
        #expect(shown.daylight.sunset == "4:44 PM")
        #expect(shown.daylight.caption == "2h 34m of light left")
        #expect(shown.note == WeatherDisplay.Note(text: "Rain likely after 6 PM", symbolName: "cloud.rain"))
        #expect(report.alerts == [])
        #expect(report.minutes == nil)
    }

    @Test func nowSlotRepeatsTheCurrentReading() throws {
        var report = try WeatherCache.makeDecoder().decode(WeatherReport.self, from: Data(cacheFixture.utf8))
        report.current.temperature = 21.1
        report.current.symbolName = "sun.max"
        let shown = display(report, at: utc("2026-11-02T20:10:00Z"))

        #expect(shown.hours.first?.temperature == shown.now.temperature)
        #expect(shown.hours.first?.symbolName == "sun.max")
        #expect(shown.hours.dropFirst().first?.temperature == "55°")
    }

    @Test func temperaturesInFahrenheitAndCelsius() {
        let now = local(2026, 11, 2, 14)
        let report = WeatherFixture.report(
            at: now,
            current: .init(temperature: -3.3),
            hour: { _ in .init(temperature: 10) },
            day: { _ in .init(high: 15.6, low: -0.4) }
        )
        let fahrenheit = display(report, at: now, unit: .fahrenheit)
        let celsius = display(report, at: now, unit: .celsius)

        #expect(fahrenheit.now.temperature == "26°")
        #expect(celsius.now.temperature == "-3°")
        #expect((fahrenheit.now.high, fahrenheit.now.low) == ("60°", "31°"))
        #expect((celsius.now.high, celsius.now.low) == ("16°", "0°"))
        #expect(fahrenheit.hours.dropFirst().map(\.temperature) == Array(repeating: "50°", count: 5))
        #expect(celsius.hours.dropFirst().map(\.temperature) == Array(repeating: "10°", count: 5))
    }

    @Test func sixHoursStartingNow() {
        let now = local(2026, 11, 2, 14, 40)
        let shown = display(WeatherFixture.report(at: now), at: now)
        #expect(shown.hours.map(\.label) == ["Now", "3 PM", "4 PM", "5 PM", "6 PM", "7 PM"])
    }

    @Test func hourLabelsCrossMidnight() {
        let now = local(2026, 11, 2, 22, 30)
        let shown = display(WeatherFixture.report(at: now), at: now)
        #expect(shown.hours.map(\.label) == ["Now", "11 PM", "12 AM", "1 AM", "2 AM", "3 AM"])
    }

    @Test func hourLabelsRepeatOneAMWhenTheClocksFallBack() {
        let now = utc("2026-11-01T05:30:00Z")
        let shown = display(WeatherFixture.report(at: now), at: now)
        #expect(shown.hours.map(\.label) == ["Now", "1 AM", "1 AM", "2 AM", "3 AM", "4 AM"])
    }

    @Test func fiveDaysFromToday() {
        let now = local(2026, 11, 2, 14)
        let report = WeatherFixture.report(at: now, day: { date in
            .init(high: Double(calendar.component(.day, from: date)))
        })
        let shown = display(report, at: now, unit: .celsius)
        #expect(report.daily.count == 10)
        #expect(shown.days.map(\.label) == ["Mon", "Tue", "Wed", "Thu", "Fri"])
        #expect(shown.days.map(\.high) == ["2°", "3°", "4°", "5°", "6°"])
    }

    @Test func fiveDaysFromTodayOnTheDSTChange() {
        let now = local(2026, 11, 1, 12)
        let shown = display(WeatherFixture.report(at: now), at: now)
        #expect(shown.days.map(\.label) == ["Sun", "Mon", "Tue", "Wed", "Thu"])
    }

    @Test(arguments: [
        (0.0, nil), (0.19, nil), (0.2, 20), (0.24, 20), (0.26, 30), (0.44, 40), (0.46, 50), (0.96, 100), (1.0, 100),
    ] as [(Double, Int?)])
    func precipitationRoundsToTensAndHidesUnderTwentyPercent(chance: Double, percent: Int?) {
        #expect(WeatherDisplay.percent(chance) == percent)
    }

    @Test(arguments: [
        ("clear", true, "Sunny"),
        ("clear", false, "Clear"),
        ("mostlyClear", true, "Mostly Sunny"),
        ("mostlyClear", false, "Mostly Clear"),
        ("partlyCloudy", true, "Partly Cloudy"),
        ("mostlyCloudy", true, "Mostly Cloudy"),
        ("thunderstorms", false, "Thunderstorms"),
        ("strongStorms", false, "Severe Thunderstorms"),
        ("isolatedThunderstorms", true, "Isolated Thunderstorms"),
        ("foggy", true, "Fog"),
        ("heavyRain", true, "Heavy Rain"),
        ("frigid", true, "Cold"),
        ("volcanicAsh", true, "Volcanic Ash"),
    ])
    func titlesMatchAppleWeather(raw: String, isDaylight: Bool, title: String) {
        #expect(WeatherConditionText.title(for: raw, isDaylight: isDaylight) == title)
    }

    @Test func currentTitleFollowsDaylight() {
        let day = local(2026, 11, 2, 12)
        let night = local(2026, 11, 2, 21)
        #expect(display(WeatherFixture.report(at: day), at: day).now.condition == "Sunny")
        #expect(display(WeatherFixture.report(at: night), at: night).now.condition == "Clear")
    }

    @Test func everyWeatherKitConditionHasAnExplicitEntry() {
        let raws = Set(WeatherKit.WeatherCondition.allCases.map(\.rawValue))
        #expect(raws == Set(WeatherConditionCatalog.entries.keys))
        #expect(raws == Set(expectedFamilies.keys))
        for raw in raws {
            let title = WeatherConditionText.title(for: raw, isDaylight: true)
            #expect(!title.isEmpty && !title.contains("\u{2014}"), "\(raw)")
        }
    }

    @Test(arguments: WeatherKit.WeatherCondition.allCases.map(\.rawValue))
    func familyMapping(raw: String) {
        #expect(ConditionFamily(weatherKitCondition: raw) == expectedFamilies[raw])
    }

    @Test func reportWithoutHoursOrDaysStillDisplays() {
        let now = local(2026, 11, 2, 12)
        var report = WeatherFixture.report(at: now)
        report.hourly = []
        report.daily = []
        let shown = display(report, at: now)
        #expect(shown.now.temperature == "50°")
        #expect((shown.now.high, shown.now.low) == ("--", "--"))
        #expect(shown.hours.isEmpty)
        #expect(shown.days.isEmpty)
        #expect(shown.note == nil)
        #expect(shown.daylight.fraction != nil)
    }

    @Test func unknownConditionFallsBackToCloudy() {
        #expect(ConditionFamily(weatherKitCondition: "volcanicAsh") == .cloudy)
    }

    @Test func pastAndFutureHoursReplay() {
        let now = local(2026, 11, 2, 14)
        let report = WeatherFixture.report(
            at: now,
            current: .init(temperature: 12, condition: "partlyCloudy"),
            hour: { date in
                switch calendar.component(.hour, from: date) {
                case 9: .init(temperature: 3, condition: "foggy")
                case 12: .init(temperature: 9, condition: "mostlyCloudy")
                case 20: .init(temperature: 6, condition: "rain", chance: 0.8)
                default: .init()
                }
            }
        )

        #expect(report.conditions(at: local(2026, 11, 2, 9, 30)).condition == "foggy")
        #expect(report.conditions(at: local(2026, 11, 2, 9, 30)).temperature == 3)
        #expect(report.conditions(at: local(2026, 11, 2, 20, 15)).condition == "rain")
        #expect(report.conditions(at: local(2026, 11, 2, 13, 20)).condition == "partlyCloudy")
        #expect(report.conditions(at: local(2026, 11, 2, 14, 40)).condition == "partlyCloudy")
        #expect(report.conditions(at: local(2026, 11, 2, 12, 59)).condition == "mostlyCloudy")

        let replay = display(report, at: local(2026, 11, 2, 9, 30))
        #expect(replay.now.temperature == "37°")
        #expect(replay.now.condition == "Fog")
        #expect(replay.now.family == .fog)
        #expect(replay.hours.first?.label == "Now")
        #expect(replay.hours.map(\.temperature).first == "37°")
    }
}

private let expectedFamilies: [String: ConditionFamily] = [
    "blizzard": .snow, "blowingDust": .fog, "blowingSnow": .snow, "breezy": .clear, "clear": .clear,
    "cloudy": .cloudy, "drizzle": .rain, "flurries": .snow, "foggy": .fog, "freezingDrizzle": .rain,
    "freezingRain": .rain, "frigid": .clear, "hail": .storm, "haze": .fog, "heavyRain": .rain,
    "heavySnow": .snow, "hot": .clear, "hurricane": .storm, "isolatedThunderstorms": .storm,
    "mostlyClear": .clear, "mostlyCloudy": .cloudy, "partlyCloudy": .partlyCloudy, "rain": .rain,
    "scatteredThunderstorms": .storm, "sleet": .snow, "smoky": .fog, "snow": .snow, "strongStorms": .storm,
    "sunFlurries": .snow, "sunShowers": .rain, "thunderstorms": .storm, "tropicalStorm": .storm,
    "windy": .clear, "wintryMix": .snow,
]

@Suite("Weather daylight")
struct WeatherDaylightTests {
    private let report = WeatherFixture.report(at: local(2026, 11, 2, 12), day: { day in
        let offset = calendar.dateComponents([.day], from: local(2026, 11, 2, 0), to: day).day ?? 0
        return .init(
            sunrise: local(2026, 11, 2 + offset, 6, 24 + offset),
            sunset: local(2026, 11, 2 + offset, 16, 44 - offset)
        )
    })

    @Test(arguments: [
        (local(2026, 11, 2, 4, 0), "Sunrise 6:24 AM"),
        (local(2026, 11, 2, 5, 0), "Sunrise in 1h 24m"),
        (local(2026, 11, 2, 6, 5), "Sunrise in 19 min"),
        (local(2026, 11, 2, 11, 29), "5h 15m of light left"),
        (local(2026, 11, 2, 11, 44), "5h of light left"),
        (local(2026, 11, 2, 15, 44), "1h of light left"),
        (local(2026, 11, 2, 16, 11), "Sunset in 33 min"),
        (local(2026, 11, 2, 16, 43), "Sunset in 1 min"),
        (local(2026, 11, 2, 16, 44), "Sunrise 6:25 AM"),
        (local(2026, 11, 2, 19, 0), "Sunrise 6:25 AM"),
        (local(2026, 11, 3, 0, 30), "Sunrise 6:25 AM"),
        (local(2026, 11, 3, 5, 0), "Sunrise in 1h 25m"),
    ])
    func captions(date: Date, caption: String) {
        #expect(display(report, at: date).daylight.caption == caption)
    }

    @Test func arcShowsTomorrowAfterSunset() {
        let evening = display(report, at: local(2026, 11, 2, 19, 0)).daylight
        #expect(evening.sunrise == "6:25 AM")
        #expect(evening.sunset == "4:43 PM")
        #expect(evening.fraction == nil)
        let afternoon = display(report, at: local(2026, 11, 2, 15, 0)).daylight
        #expect(afternoon.sunrise == "6:24 AM")
        #expect(afternoon.sunset == "4:44 PM")
    }

    @Test func fractionRunsFromSunriseToSunset() throws {
        let daylight = display(report, at: local(2026, 11, 2, 11, 29)).daylight
        let fraction = try #require(daylight.fraction)
        #expect(abs(fraction - 305.0 / 620.0) < 1e-9)
        #expect(display(report, at: local(2026, 11, 2, 6, 24)).daylight.fraction == 0)
        #expect(display(report, at: local(2026, 11, 2, 6, 0)).daylight.fraction == nil)
        #expect(display(report, at: local(2026, 11, 2, 19, 0)).daylight.fraction == nil)
        #expect(daylight.sunrise == "6:24 AM")
        #expect(daylight.sunset == "4:44 PM")
    }

    @Test func fallsBackToTheSunMathWhenTheDayHasNoTimes() throws {
        let noon = local(2026, 11, 2, 12)
        let missingTimes = WeatherFixture.report(at: noon, day: { _ in .init(sunrise: .some(nil), sunset: .some(nil)) })
        var missingDay = WeatherFixture.report(at: noon)
        missingDay.daily = []
        let sunrise = try #require(SolarPosition.sunrise(on: noon, location: WeatherFixture.chicago, timeZone: calendar.timeZone))
        let sunset = try #require(SolarPosition.sunset(on: noon, location: WeatherFixture.chicago, timeZone: calendar.timeZone))

        for report in [missingTimes, missingDay] {
            let daylight = display(report, at: noon).daylight
            #expect(daylight.sunrise == ClockLabel.string(sunrise, calendar: calendar))
            #expect(daylight.sunset == ClockLabel.string(sunset, calendar: calendar))
            #expect(daylight.fraction != nil)
            #expect(daylight.caption.hasSuffix("of light left"))
        }
    }
}

@Suite("Weather note rules")
struct WeatherNoteTests {
    private func note(_ report: WeatherReport, at date: Date, calendar: Calendar = calendar) -> WeatherDisplay.Note? {
        WeatherDisplay(report: report, at: date, calendar: calendar, unit: .fahrenheit).note
    }

    private func from(_ start: Date, to end: Date? = nil, _ spec: WeatherFixture.HourSpec) -> (Date) -> WeatherFixture.HourSpec {
        { date in date >= start && date < (end ?? .distantFuture) ? spec : .init() }
    }

    private let afternoon = local(2026, 11, 2, 14)

    @Test func rainLikelyAhead() {
        let report = WeatherFixture.report(at: afternoon, hour: from(local(2026, 11, 2, 21), .init(condition: "rain", chance: 0.6)))
        #expect(note(report, at: afternoon) == .init(text: "Rain likely after 9 PM", symbolName: "cloud.rain"))
    }

    @Test func chanceOfRainAhead() {
        let report = WeatherFixture.report(at: afternoon, hour: from(local(2026, 11, 2, 21), .init(condition: "cloudy", chance: 0.4)))
        #expect(note(report, at: afternoon) == .init(text: "Chance of rain after 9 PM", symbolName: "cloud.rain"))
    }

    @Test func likelyBeatsAnEarlierChance() {
        let report = WeatherFixture.report(at: afternoon, hour: { date in
            if date >= local(2026, 11, 2, 21) { return .init(condition: "rain", chance: 0.7) }
            if date >= local(2026, 11, 2, 18) { return .init(condition: "cloudy", chance: 0.4) }
            return .init()
        })
        #expect(note(report, at: afternoon)?.text == "Rain likely after 9 PM")
    }

    @Test func snowAndStormsAhead() {
        let snow = WeatherFixture.report(at: afternoon, hour: from(local(2026, 11, 2, 21), .init(temperature: -1, condition: "snow", chance: 0.7)))
        let freezing = WeatherFixture.report(at: afternoon, hour: from(local(2026, 11, 2, 21), .init(temperature: -2, condition: "cloudy", chance: 0.6)))
        let storms = WeatherFixture.report(at: afternoon, hour: from(local(2026, 11, 2, 19), .init(condition: "thunderstorms", chance: 0.6)))
        let chanceOfStorms = WeatherFixture.report(at: afternoon, hour: from(local(2026, 11, 2, 19), .init(condition: "scatteredThunderstorms", chance: 0.3)))
        #expect(note(snow, at: afternoon) == .init(text: "Snow likely after 9 PM", symbolName: "cloud.snow"))
        #expect(note(freezing, at: afternoon)?.text == "Snow likely after 9 PM")
        #expect(note(storms, at: afternoon) == .init(text: "Storms likely after 7 PM", symbolName: "cloud.bolt.rain"))
        #expect(note(chanceOfStorms, at: afternoon)?.text == "Chance of storms after 7 PM")
    }

    @Test func rainBeyondTwelveHoursIsNotMentioned() {
        let report = WeatherFixture.report(at: afternoon, hour: from(local(2026, 11, 3, 4), .init(condition: "rain", chance: 0.9)))
        #expect(note(report, at: afternoon)?.text == "Clear skies through the evening")
    }

    @Test func hourNamesUseTheCalendarTimeZone() {
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let report = WeatherFixture.report(at: afternoon, hour: from(local(2026, 11, 2, 21), .init(condition: "rain", chance: 0.6)))
        #expect(note(report, at: afternoon, calendar: utcCalendar)?.text == "Rain likely after 3 AM")
    }

    @Test func taperingOffAtTheFirstDryHour() {
        let report = WeatherFixture.report(
            at: afternoon,
            current: .init(condition: "rain", chance: 0.9),
            hour: { date in date < local(2026, 11, 2, 18) ? .init(condition: "rain", chance: 0.8) : .init(condition: "cloudy", chance: 0.1) }
        )
        #expect(note(report, at: afternoon) == .init(text: "Tapering off around 6 PM", symbolName: "cloud.rain"))
    }

    @Test func rainThroughTheEvening() {
        let report = WeatherFixture.report(at: afternoon, hour: { _ in .init(condition: "heavyRain", chance: 0.9) })
        #expect(note(report, at: afternoon) == .init(text: "Rain through the evening", symbolName: "cloud.rain"))
    }

    @Test func snowThroughTheNight() {
        let evening = local(2026, 11, 2, 20)
        let report = WeatherFixture.report(at: evening, hour: { _ in .init(temperature: -3, condition: "snow", chance: 0.9) })
        #expect(note(report, at: evening) == .init(text: "Snow through the night", symbolName: "cloud.snow"))
    }

    @Test func fogLifting() {
        let morning = local(2026, 11, 2, 7, 30)
        let report = WeatherFixture.report(
            at: morning,
            current: .init(condition: "foggy"),
            hour: { date in date < local(2026, 11, 2, 10) ? .init(condition: "foggy") : .init() }
        )
        #expect(note(report, at: morning) == .init(text: "Lifting by 10 AM", symbolName: "sun.haze"))
    }

    @Test func fogThroughTheMorning() {
        let early = local(2026, 11, 2, 4)
        let report = WeatherFixture.report(at: early, hour: { _ in .init(condition: "foggy") })
        #expect(note(report, at: early) == .init(text: "Fog through the morning", symbolName: "cloud.fog"))
    }

    @Test func lowJustBeforeSunrise() {
        let night = local(2026, 11, 2, 22)
        let start = local(2026, 11, 2, 22)
        let report = WeatherFixture.report(at: night, hour: { date in
            let hours = date.timeIntervalSince(start) / 3600
            return .init(temperature: hours <= 8 ? 8 - max(hours, 0) * 0.65 : 2.8 + (hours - 8))
        })
        #expect(note(report, at: night) == .init(text: "Low of 37° just before sunrise", symbolName: "thermometer.low"))
    }

    @Test func lowEarlierInTheNight() {
        let night = local(2026, 11, 2, 22)
        let report = WeatherFixture.report(at: night, hour: { date in
            date == local(2026, 11, 3, 3) ? .init(temperature: 2.8) : .init(temperature: 8)
        })
        #expect(note(report, at: night)?.text == "Low of 37° around 3 AM")
    }

    @Test func highLaterInTheDay() {
        let morning = local(2026, 11, 2, 9)
        let peak = local(2026, 11, 2, 14)
        let warming: (Date) -> WeatherFixture.HourSpec = { date in
            .init(temperature: 14.5 - abs(date.timeIntervalSince(peak) / 3600))
        }
        let report = WeatherFixture.report(at: morning, hour: warming, day: { _ in .init(high: 14.5) })
        let warmerDay = WeatherFixture.report(at: morning, hour: warming, day: { _ in .init(high: 15.2) })
        #expect(note(report, at: morning) == .init(text: "High of 58° around 2 PM", symbolName: "thermometer.high"))
        #expect(note(warmerDay, at: morning)?.text == "High of 59° around 2 PM")
    }

    @Test func highThatAlreadyPassedIsNotQuoted() {
        let now = local(2026, 11, 2, 14)
        let temperatures: [Date: Double] = [
            local(2026, 11, 2, 12): 22.2, now: 18.9, local(2026, 11, 2, 15): 19.4, local(2026, 11, 2, 16): 19.0,
        ]
        let report = WeatherFixture.report(
            at: now,
            hour: { .init(temperature: temperatures[$0] ?? 10) },
            day: { _ in .init(high: 22.2) }
        )
        #expect(note(report, at: now)?.text == "High of 67° around 3 PM")
    }

    @Test func clearSkiesThroughTheEvening() {
        let report = WeatherFixture.report(at: afternoon)
        #expect(note(report, at: afternoon) == .init(text: "Clear skies through the evening", symbolName: "sun.max"))
    }

    @Test func partlyCloudyThroughTheNight() {
        let night = local(2026, 11, 2, 22)
        let report = WeatherFixture.report(at: night, hour: { _ in .init(condition: "partlyCloudy") })
        #expect(note(report, at: night) == .init(text: "Partly cloudy through the night", symbolName: "cloud.moon"))
    }

    @Test func noNoteWhenNothingStandsOut() {
        let report = WeatherFixture.report(at: afternoon, hour: from(local(2026, 11, 2, 18), .init(condition: "cloudy")))
        #expect(note(report, at: afternoon) == nil)
    }

    @Test func noteTextsAvoidEmDashes() {
        let reports = [
            WeatherFixture.report(at: afternoon),
            WeatherFixture.report(at: afternoon, hour: { _ in .init(condition: "rain", chance: 0.9) }),
        ]
        for report in reports {
            let shown = display(report, at: afternoon)
            let texts = [shown.note?.text ?? "", shown.daylight.caption, shown.now.condition]
            #expect(texts.allSatisfy { !$0.contains("\u{2014}") })
        }
    }
}
