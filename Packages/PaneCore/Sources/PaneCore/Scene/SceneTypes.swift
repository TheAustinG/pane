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

extension ScenePalette {
    /// Blends toward `other` in OKLab. Particles of the same kind blend their intensity; a change
    /// of kind fades the old layer out over the first half and the new one in over the second.
    public func interpolated(to other: ScenePalette, fraction: Double) -> ScenePalette {
        let t = min(max(fraction, 0), 1)
        return blended(
            to: other,
            fraction: t,
            colors: zip(colors, other.colors).map { $0.interpolated(to: $1, fraction: t) },
            accent: accent.interpolated(to: other.accent, fraction: t)
        )
    }

    func blended(to other: ScenePalette, fraction t: Double, colors: [RGB], accent: RGB) -> ScenePalette {
        let kind: ParticleKind
        let intensity: Double
        if particles == other.particles {
            kind = particles
            intensity = particleIntensity + (other.particleIntensity - particleIntensity) * t
        } else if t < 0.5 {
            kind = particles
            intensity = particleIntensity * (1 - 2 * t)
        } else {
            kind = other.particles
            intensity = other.particleIntensity * (2 * t - 1)
        }
        return ScenePalette(
            colors: colors,
            accent: accent,
            glassShade: glassShade + (other.glassShade - glassShade) * t,
            particles: kind,
            particleIntensity: intensity
        )
    }

    /// The largest OKLab distance between matching sky colors or the accents.
    public func colorDistance(to other: ScenePalette) -> Double {
        zip(colors, other.colors).reduce(accent.distance(to: other.accent)) { max($0, $1.0.distance(to: $1.1)) }
    }

    /// How strongly `kind` shows in this palette: the intensity for its own kind, otherwise 0.
    public func particleWeight(for kind: ParticleKind) -> Double {
        kind == particles && kind != .none ? particleIntensity : 0
    }

    /// The largest change in any particle layer's weight between the two palettes.
    public func particleDistance(to other: ScenePalette) -> Double {
        ParticleKind.allCases.reduce(0) { max($0, abs(particleWeight(for: $1) - other.particleWeight(for: $1))) }
    }
}
