#if DEBUG
import PaneCore
import SwiftUI

/// Static scene samples for the design preview. The live scene engine replaces these palettes with
/// values interpolated from condition and sun altitude; the anchors here are the same tokens.
struct ScenePreset: Identifiable {
    enum Particles {
        case none, stars, rain, snow, fog, storm
    }

    struct Hour {
        let label: String
        let symbol: String
        let temp: String
        var pop: Int?
    }

    struct Day {
        let label: String
        let symbol: String
        let high: String
        let low: String
    }

    let id: String
    let name: String
    let colors: [UInt32]
    let accent: UInt32
    let glassShade: Double
    let particles: Particles
    let time: String
    let meridiem: String
    let date: String
    let condition: String
    let symbol: String
    let temp: String
    let high: String
    let low: String
    let note: String
    let noteSymbol: String
    let arcFraction: Double?
    let arcCaption: String
    let hourly: [Hour]

    var accentColor: Color { Color(hex: accent) }

    static let daily: [Day] = [
        Day(label: "Mon", symbol: "cloud.rain", high: "54°", low: "41°"),
        Day(label: "Tue", symbol: "cloud.sun", high: "57°", low: "39°"),
        Day(label: "Wed", symbol: "sun.max", high: "60°", low: "42°"),
        Day(label: "Thu", symbol: "cloud", high: "55°", low: "40°"),
        Day(label: "Fri", symbol: "sun.max", high: "58°", low: "38°"),
    ]

    static let golden = ScenePreset(
        id: "golden", name: "Golden hour",
        colors: [0x1E2148, 0x4A3F7A, 0xB9708A, 0xEFA06A, 0x31507E], accent: 0xFFC896, glassShade: 0.20,
        particles: .none, time: "4:12", meridiem: "PM", date: "Sunday, November 1",
        condition: "Partly Cloudy", symbol: "cloud.sun", temp: "52°", high: "58°", low: "41°",
        note: "Rain likely after 9 PM", noteSymbol: "umbrella", arcFraction: 0.93, arcCaption: "Sunset in 33 min",
        hourly: [
            Hour(label: "Now", symbol: "cloud.sun", temp: "52°"),
            Hour(label: "5 PM", symbol: "cloud.sun", temp: "49°"),
            Hour(label: "6 PM", symbol: "cloud", temp: "47°"),
            Hour(label: "7 PM", symbol: "cloud", temp: "46°"),
            Hour(label: "8 PM", symbol: "cloud", temp: "45°", pop: 30),
            Hour(label: "9 PM", symbol: "cloud.rain", temp: "44°", pop: 60),
        ]
    )

    static let day = ScenePreset(
        id: "day", name: "Clear day",
        colors: [0x123F75, 0x2163AD, 0x5596D4, 0xE4D3A0, 0x1B5597], accent: 0xFFEAAF, glassShade: 0.32,
        particles: .none, time: "11:30", meridiem: "AM", date: "Sunday, November 1",
        condition: "Sunny", symbol: "sun.max", temp: "61°", high: "63°", low: "44°",
        note: "Clear skies through the evening", noteSymbol: "sun.max", arcFraction: 0.5,
        arcCaption: "5h 15m of light left",
        hourly: [
            Hour(label: "Now", symbol: "sun.max", temp: "61°"),
            Hour(label: "12 PM", symbol: "sun.max", temp: "62°"),
            Hour(label: "1 PM", symbol: "sun.max", temp: "63°"),
            Hour(label: "2 PM", symbol: "cloud.sun", temp: "63°"),
            Hour(label: "3 PM", symbol: "cloud.sun", temp: "62°"),
            Hour(label: "4 PM", symbol: "sun.max", temp: "60°"),
        ]
    )

    static let rain = ScenePreset(
        id: "rain", name: "Rain",
        colors: [0x1C232D, 0x364352, 0x58687A, 0x6E8094, 0x283442], accent: 0xAAD0EE, glassShade: 0.16,
        particles: .rain, time: "2:05", meridiem: "PM", date: "Sunday, November 1",
        condition: "Light Rain", symbol: "cloud.rain", temp: "47°", high: "50°", low: "42°",
        note: "Tapering off around 6 PM", noteSymbol: "umbrella", arcFraction: 0.65, arcCaption: "Sunset 4:45 PM",
        hourly: [
            Hour(label: "Now", symbol: "cloud.rain", temp: "47°", pop: 80),
            Hour(label: "3 PM", symbol: "cloud.rain", temp: "47°", pop: 70),
            Hour(label: "4 PM", symbol: "cloud.rain", temp: "46°", pop: 60),
            Hour(label: "5 PM", symbol: "cloud.rain", temp: "46°", pop: 40),
            Hour(label: "6 PM", symbol: "cloud", temp: "45°", pop: 20),
            Hour(label: "7 PM", symbol: "cloud", temp: "44°"),
        ]
    )

    static let night = ScenePreset(
        id: "night", name: "Night",
        colors: [0x050816, 0x111838, 0x232A58, 0x3B356A, 0x0B1230], accent: 0xB2BCFF, glassShade: 0.10,
        particles: .stars, time: "10:48", meridiem: "PM", date: "Sunday, November 1",
        condition: "Clear", symbol: "moon.stars", temp: "39°", high: "58°", low: "37°",
        note: "Low of 37° just before sunrise", noteSymbol: "thermometer.low", arcFraction: nil, arcCaption: "Night",
        hourly: [
            Hour(label: "Now", symbol: "moon", temp: "39°"),
            Hour(label: "12 AM", symbol: "moon", temp: "38°"),
            Hour(label: "1 AM", symbol: "moon", temp: "38°"),
            Hour(label: "2 AM", symbol: "moon", temp: "37°"),
            Hour(label: "3 AM", symbol: "moon", temp: "37°"),
            Hour(label: "4 AM", symbol: "moon", temp: "37°"),
        ]
    )

    static let dawn = ScenePreset(
        id: "dawn", name: "Blue hour",
        colors: [0x151A3E, 0x2E2F66, 0x6B5287, 0xD98F86, 0x223463], accent: 0xFFC8B4, glassShade: 0.16,
        particles: .none, time: "6:04", meridiem: "AM", date: "Monday, November 2",
        condition: "Clear", symbol: "sun.horizon", temp: "38°", high: "57°", low: "37°",
        note: "Sunrise in 19 min", noteSymbol: "sunrise", arcFraction: nil, arcCaption: "Sunrise in 19 min",
        hourly: [
            Hour(label: "Now", symbol: "moon", temp: "38°"),
            Hour(label: "7 AM", symbol: "sun.horizon", temp: "39°"),
            Hour(label: "8 AM", symbol: "sun.max", temp: "43°"),
            Hour(label: "9 AM", symbol: "sun.max", temp: "47°"),
            Hour(label: "10 AM", symbol: "cloud.sun", temp: "51°"),
            Hour(label: "11 AM", symbol: "cloud.sun", temp: "54°"),
        ]
    )

    static let snow = ScenePreset(
        id: "snow", name: "Snow",
        colors: [0x3C4757, 0x66748A, 0x9AA8B9, 0xC9D2DC, 0x4F5D72], accent: 0xE6F0FF, glassShade: 0.36,
        particles: .snow, time: "9:20", meridiem: "AM", date: "Tuesday, December 8",
        condition: "Light Snow", symbol: "cloud.snow", temp: "29°", high: "31°", low: "22°",
        note: "1 to 2 inches by noon", noteSymbol: "snowflake", arcFraction: 0.28, arcCaption: "6h 40m of light left",
        hourly: [
            Hour(label: "Now", symbol: "cloud.snow", temp: "29°", pop: 90),
            Hour(label: "10 AM", symbol: "cloud.snow", temp: "29°", pop: 90),
            Hour(label: "11 AM", symbol: "cloud.snow", temp: "30°", pop: 70),
            Hour(label: "12 PM", symbol: "cloud.snow", temp: "31°", pop: 50),
            Hour(label: "1 PM", symbol: "cloud", temp: "31°", pop: 20),
            Hour(label: "2 PM", symbol: "cloud", temp: "30°"),
        ]
    )

    static let fog = ScenePreset(
        id: "fog", name: "Fog",
        colors: [0x3A3F47, 0x5D646E, 0x8B929B, 0xB1B6BC, 0x4A5058], accent: 0xD7DCE2, glassShade: 0.30,
        particles: .fog, time: "7:45", meridiem: "AM", date: "Wednesday, November 4",
        condition: "Foggy", symbol: "cloud.fog", temp: "44°", high: "56°", low: "42°",
        note: "Lifting by 10 AM", noteSymbol: "eye", arcFraction: 0.08, arcCaption: "9h 10m of light left",
        hourly: [
            Hour(label: "Now", symbol: "cloud.fog", temp: "44°"),
            Hour(label: "8 AM", symbol: "cloud.fog", temp: "45°"),
            Hour(label: "9 AM", symbol: "cloud.fog", temp: "47°"),
            Hour(label: "10 AM", symbol: "cloud", temp: "50°"),
            Hour(label: "11 AM", symbol: "cloud.sun", temp: "53°"),
            Hour(label: "12 PM", symbol: "cloud.sun", temp: "55°"),
        ]
    )

    static let storm = ScenePreset(
        id: "storm", name: "Storm",
        colors: [0x15161F, 0x2B2C40, 0x4B4662, 0x645C7E, 0x1F2030], accent: 0xC8B8FF, glassShade: 0.14,
        particles: .storm, time: "7:21", meridiem: "PM", date: "Sunday, November 1",
        condition: "Thunderstorms", symbol: "cloud.bolt.rain", temp: "58°", high: "66°", low: "49°",
        note: "Storms until about 9 PM", noteSymbol: "cloud.bolt", arcFraction: nil, arcCaption: "Night",
        hourly: [
            Hour(label: "Now", symbol: "cloud.bolt.rain", temp: "58°", pop: 90),
            Hour(label: "8 PM", symbol: "cloud.bolt.rain", temp: "56°", pop: 80),
            Hour(label: "9 PM", symbol: "cloud.rain", temp: "54°", pop: 60),
            Hour(label: "10 PM", symbol: "cloud", temp: "52°", pop: 20),
            Hour(label: "11 PM", symbol: "cloud.moon", temp: "51°"),
            Hour(label: "12 AM", symbol: "moon", temp: "50°"),
        ]
    )

    static let all: [ScenePreset] = [golden, day, rain, night, dawn, snow, fog, storm]

    static func named(_ id: String?) -> ScenePreset? {
        all.first { $0.id == id }
    }

    /// The sample whose scene the app is showing; golden when the live scene is.
    static func matching(_ scene: WeatherScene?) -> ScenePreset {
        guard let scene else { return .golden }
        return all.first { WeatherScene.preset(named: $0.id) == scene } ?? .golden
    }

    /// The frozen app time that makes the real clock read this sample's time and date.
    var sampleDate: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy EEEE, MMMM d h:mm a"
        return formatter.date(from: "2026 \(date) \(time) \(meridiem)")
    }

    /// Deterministic contribution levels with a 12-day streak ending today.
    static let contributionLevels: [Int] = {
        var seed: UInt64 = 11
        func unit() -> Double {
            seed = (seed &* 6364136223846793005 &+ 1442695040888963407)
            return Double(seed >> 33) / Double(1 << 31)
        }
        let today = 25 * 7 + 3
        return (0..<(26 * 7)).map { index in
            let r = unit()
            if index > today { return -1 }
            if index > today - 12 { return 1 + Int(r * 4) }
            if index == today - 12 { return 0 }
            return r < 0.38 ? 0 : r < 0.62 ? 1 : r < 0.82 ? 2 : r < 0.94 ? 3 : 4
        }
    }()
}
#endif
