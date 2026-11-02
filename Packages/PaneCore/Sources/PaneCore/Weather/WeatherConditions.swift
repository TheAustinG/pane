import Foundation

/// Every `WeatherKit.WeatherCondition` case by raw value: the scene family and the title Apple
/// Weather shows. A test checks this table against the SDK's `allCases`.
enum WeatherConditionCatalog {
    struct Entry: Hashable, Sendable {
        let family: ConditionFamily
        let title: String
        /// Apple Weather says "Sunny" where WeatherKit says "Clear" during the day.
        let daytimeTitle: String?

        init(_ family: ConditionFamily, _ title: String, daytime: String? = nil) {
            self.family = family
            self.title = title
            self.daytimeTitle = daytime
        }
    }

    static let entries: [String: Entry] = [
        "blizzard": Entry(.snow, "Blizzard"),
        "blowingDust": Entry(.fog, "Dust"),
        "blowingSnow": Entry(.snow, "Blowing Snow"),
        "breezy": Entry(.clear, "Breezy"),
        "clear": Entry(.clear, "Clear", daytime: "Sunny"),
        "cloudy": Entry(.cloudy, "Cloudy"),
        "drizzle": Entry(.rain, "Drizzle"),
        "flurries": Entry(.snow, "Flurries"),
        "foggy": Entry(.fog, "Fog"),
        "freezingDrizzle": Entry(.rain, "Freezing Drizzle"),
        "freezingRain": Entry(.rain, "Freezing Rain"),
        "frigid": Entry(.clear, "Cold"),
        "hail": Entry(.storm, "Hail"),
        "haze": Entry(.fog, "Haze"),
        "heavyRain": Entry(.rain, "Heavy Rain"),
        "heavySnow": Entry(.snow, "Heavy Snow"),
        "hot": Entry(.clear, "Hot"),
        "hurricane": Entry(.storm, "Hurricane"),
        "isolatedThunderstorms": Entry(.storm, "Isolated Thunderstorms"),
        "mostlyClear": Entry(.clear, "Mostly Clear", daytime: "Mostly Sunny"),
        "mostlyCloudy": Entry(.cloudy, "Mostly Cloudy"),
        "partlyCloudy": Entry(.partlyCloudy, "Partly Cloudy"),
        "rain": Entry(.rain, "Rain"),
        "scatteredThunderstorms": Entry(.storm, "Scattered Thunderstorms"),
        "sleet": Entry(.snow, "Sleet"),
        "smoky": Entry(.fog, "Smoke"),
        "snow": Entry(.snow, "Snow"),
        "strongStorms": Entry(.storm, "Severe Thunderstorms"),
        "sunFlurries": Entry(.snow, "Sun Flurries"),
        "sunShowers": Entry(.rain, "Sun Showers"),
        "thunderstorms": Entry(.storm, "Thunderstorms"),
        "tropicalStorm": Entry(.storm, "Tropical Storm"),
        "windy": Entry(.clear, "Windy"),
        "wintryMix": Entry(.snow, "Wintry Mix"),
    ]
}

extension ConditionFamily {
    /// Maps `WeatherKit.WeatherCondition.rawValue` to the scene engine's families. A raw value
    /// from a newer SDK falls back to cloudy, the most neutral sky.
    public init(weatherKitCondition raw: String) {
        self = WeatherConditionCatalog.entries[raw]?.family ?? .cloudy
    }
}

enum WeatherConditionText {
    static func title(for raw: String, isDaylight: Bool) -> String {
        guard let entry = WeatherConditionCatalog.entries[raw] else { return splitCamelCase(raw) }
        return isDaylight ? entry.daytimeTitle ?? entry.title : entry.title
    }

    static func splitCamelCase(_ raw: String) -> String {
        var words: [String] = []
        var word = ""
        for character in raw {
            if character.isUppercase, !word.isEmpty {
                words.append(word)
                word = ""
            }
            word.append(character)
        }
        if !word.isEmpty { words.append(word) }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
