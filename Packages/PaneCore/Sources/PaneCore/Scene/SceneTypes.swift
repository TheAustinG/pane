import Foundation

public struct GeoPoint: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum ConditionFamily: String, CaseIterable, Hashable, Sendable, Codable {
    case clear
    case partlyCloudy
    case cloudy
    case rain
    case storm
    case snow
    case fog
}

/// What the background shows: a condition family under the sun at a given altitude.
public struct WeatherScene: Hashable, Sendable {
    public var condition: ConditionFamily
    /// Degrees above the horizon; negative below it.
    public var sunAltitude: Double
    /// Dawn and dusk share altitudes; this tells them apart.
    public var isMorning: Bool

    public init(condition: ConditionFamily, sunAltitude: Double, isMorning: Bool) {
        self.condition = condition
        self.sunAltitude = sunAltitude
        self.isMorning = isMorning
    }
}

public struct RGB: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

public enum ParticleKind: String, CaseIterable, Hashable, Sendable, Codable {
    case none
    case stars
    case rain
    case snow
    case fog
    case storm
}

public struct ScenePalette: Hashable, Sendable {
    /// Five colors: top left, top right, center, low glow, bottom.
    public var colors: [RGB]
    public var accent: RGB
    /// Opacity of the dark shade mixed into glass panes.
    public var glassShade: Double
    public var particles: ParticleKind
    /// 0 to 1: how strongly the particle layer shows.
    public var particleIntensity: Double

    public init(colors: [RGB], accent: RGB, glassShade: Double, particles: ParticleKind, particleIntensity: Double) {
        self.colors = colors
        self.accent = accent
        self.glassShade = glassShade
        self.particles = particles
        self.particleIntensity = particleIntensity
    }
}

public enum SceneEngine {
    public static func palette(for scene: WeatherScene) -> ScenePalette {
        ScenePalette(
            colors: [0x1E2148, 0x4A3F7A, 0xB9708A, 0xEFA06A, 0x31507E].map { RGB(hex: $0) },
            accent: RGB(hex: 0xFFC896),
            glassShade: 0.2,
            particles: .none,
            particleIntensity: 0
        )
    }

    public static func scene(condition: ConditionFamily, at date: Date, location: GeoPoint) -> WeatherScene {
        WeatherScene(
            condition: condition,
            sunAltitude: SolarPosition.altitude(at: date, location: location),
            isMorning: true
        )
    }
}

public enum SolarPosition {
    /// Sun altitude in degrees, NOAA solar position algorithm.
    public static func altitude(at date: Date, location: GeoPoint) -> Double {
        0
    }
}

extension WeatherScene {
    /// Fixed scenes for `-scene` and the debug menu: golden, day, rain, night, dawn, snow, fog, storm.
    public static let presetNames = ["golden", "day", "rain", "night", "dawn", "snow", "fog", "storm"]

    public static func preset(named name: String) -> WeatherScene? {
        presetNames.contains(name) ? WeatherScene(condition: .clear, sunAltitude: 4, isMorning: false) : nil
    }
}
