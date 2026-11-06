import Testing
@testable import PaneCore

private func time(_ altitude: Double, morning: Bool) -> TimeOfDay {
    BackgroundPolicy.timeOfDay(for: WeatherScene(condition: .clear, sunAltitude: altitude, isMorning: morning))
}

@Suite("Photo selection")
struct PhotoSelectionTests {
    @Test(arguments: [
        (-30.0, TimeOfDay.night, TimeOfDay.night),
        (-6.01, .night, .night),
        (-6, .dawn, .dusk),
        (-3, .dawn, .dusk),
        (0, .dawn, .dusk),
        (7.99, .dawn, .dusk),
        (8, .day, .day),
        (60, .day, .day),
    ])
    func timeOfDayEdges(altitude: Double, morning: TimeOfDay, evening: TimeOfDay) {
        #expect(time(altitude, morning: true) == morning)
        #expect(time(altitude, morning: false) == evening)
    }

    @Test func everyPresetPicksItsPhoto() {
        let expected: [String: String] = [
            "golden": "clear-dusk",
            "day": "clear-day",
            "rain": "rain-day",
            "night": "clear-night",
            "dawn": "clear-dawn",
            "snow": "snow-day",
            "fog": "fog-day",
            "storm": "storm-day",
        ]
        #expect(Set(expected.keys) == Set(WeatherScene.presetNames))
        for name in WeatherScene.presetNames {
            let scene = WeatherScene.preset(named: name)!
            #expect(BackgroundPolicy.photoKey(for: scene).name == expected[name], "preset \(name)")
        }
    }

    @Test func photoKeyKeepsTheSceneCondition() {
        for condition in ConditionFamily.allCases {
            let scene = WeatherScene(condition: condition, sunAltitude: 20, isMorning: true)
            #expect(BackgroundPolicy.photoKey(for: scene) == PhotoKey(condition: condition, time: .day))
        }
    }

    @Test func allHasTwentyEightUniqueSlots() {
        #expect(PhotoKey.all.count == 28)
        #expect(Set(PhotoKey.all).count == 28)
        #expect(Set(PhotoKey.all.map(\.name)).count == 28)
        #expect(PhotoKey.all.first?.name == "clear-dawn")
        #expect(PhotoKey.all.last?.name == "fog-night")
    }

    @Test(arguments: PhotoKey.all)
    func nameRoundTrips(_ key: PhotoKey) {
        #expect(PhotoKey(name: key.name) == key)
    }

    @Test(arguments: ["", "clear", "clear-", "-day", "clear-noon", "sunny-day", "clear-day-2", "Clear-day", "partly-cloudy-day"])
    func unknownNamesAreRejected(_ name: String) {
        #expect(PhotoKey(name: name) == nil)
    }

    @Test func partlyCloudyNameUsesTheRawValue() {
        #expect(PhotoKey(condition: .partlyCloudy, time: .dusk).name == "partlyCloudy-dusk")
    }
}
