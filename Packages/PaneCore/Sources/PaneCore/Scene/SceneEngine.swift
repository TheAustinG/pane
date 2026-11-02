import Foundation

/// Turns a scene into the sky's palette, from the anchors and condition overlays in
/// `.impeccable/design.json` (`extensions.scenes`).
public enum SceneEngine {
    public static func palette(for scene: WeatherScene) -> ScenePalette {
        let sky = SkyState.at(altitude: scene.sunAltitude, isMorning: scene.isMorning)
        let mixed = overlay(for: scene.condition).map { sky.covered(by: $0) } ?? sky
        let particles = particles(for: scene.condition, altitude: scene.sunAltitude)
        return ScenePalette(
            colors: mixed.colors.map(\.rgb),
            accent: mixed.accent.rgb,
            glassShade: min(max(mixed.glassShade, SkyState.minGlassShade), SkyState.maxGlassShade),
            particles: particles.kind,
            particleIntensity: particles.intensity
        )
    }

    public static func scene(condition: ConditionFamily, at date: Date, location: GeoPoint) -> WeatherScene {
        WeatherScene(
            condition: condition,
            sunAltitude: SolarPosition.altitude(at: date, location: location),
            isMorning: SolarPosition.hourAngle(at: date, location: location) < 0
        )
    }

    /// Stars start to show at this altitude and reach full strength at the night anchor.
    static let starsAppear = -6.0

    private static func overlay(for condition: ConditionFamily) -> ConditionOverlay? {
        switch condition {
        case .clear: nil
        case .partlyCloudy: .partlyCloudy
        case .cloudy: .cloudy
        case .rain: .rain
        case .storm: .storm
        case .snow: .snow
        case .fog: .fog
        }
    }

    private static func particles(for condition: ConditionFamily, altitude: Double) -> (kind: ParticleKind, intensity: Double) {
        let stars = smoothstep((starsAppear - altitude) / (starsAppear - SkyState.nightAltitude))
        switch condition {
        case .clear:
            return stars > 0 ? (.stars, stars) : (.none, 0)
        case .partlyCloudy:
            return stars > 0 ? (.stars, stars * 0.6) : (.none, 0)
        case .cloudy:
            return (.none, 0)
        case .rain:
            return (.rain, 1)
        case .storm:
            return (.storm, 1)
        case .snow:
            return (.snow, 1)
        case .fog:
            // White bands read far brighter against a night sky than a day one.
            return (.fog, 0.6 + 0.4 * smoothstep((altitude - SkyState.nightAltitude) / -SkyState.nightAltitude))
        }
    }
}

func smoothstep(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

struct SkyState {
    var colors: [OKLab]
    var accent: OKLab
    var glassShade: Double

    init(colors: [UInt32], accent: UInt32, glassShade: Double) {
        self.colors = colors.map { OKLab(RGB(hex: $0)) }
        self.accent = OKLab(RGB(hex: accent))
        self.glassShade = glassShade
    }

    private init(colors: [OKLab], accent: OKLab, glassShade: Double) {
        self.colors = colors
        self.accent = accent
        self.glassShade = glassShade
    }

    static let night = SkyState(colors: [0x050816, 0x111838, 0x232A58, 0x3B356A, 0x0B1230], accent: 0xB2BCFF, glassShade: 0.10)
    static let blueHour = SkyState(colors: [0x151A3E, 0x2E2F66, 0x6B5287, 0xD98F86, 0x223463], accent: 0xFFC8B4, glassShade: 0.16)
    static let goldenHour = SkyState(colors: [0x1E2148, 0x4A3F7A, 0xB9708A, 0xEFA06A, 0x31507E], accent: 0xFFC896, glassShade: 0.20)
    static let day = SkyState(colors: [0x123F75, 0x2163AD, 0x5596D4, 0xE4D3A0, 0x1B5597], accent: 0xFFEAAF, glassShade: 0.32)

    static let nightAltitude = -12.0
    static let blueHourAltitude = -4.0
    static let goldenHourRange = 0.0...8.0
    static let dayAltitude = 25.0
    static let minGlassShade = 0.10
    static let maxGlassShade = 0.36

    private static let knots: [(altitude: Double, sky: SkyState)] = [
        (nightAltitude, night),
        (blueHourAltitude, blueHour),
        (goldenHourRange.lowerBound, goldenHour),
        (goldenHourRange.upperBound, goldenHour),
        (dayAltitude, day),
    ]

    /// The anchor sky for a sun altitude. Neighboring anchors blend with a smoothstep, so the
    /// color is continuous and its rate of change is too: the sky settles into each anchor
    /// instead of turning a corner at it.
    static func at(altitude: Double, isMorning: Bool) -> SkyState {
        var sky = anchor(at: altitude)
        if isMorning {
            sky.applyDawnTint(weight: dawnWeight(at: altitude))
        }
        return sky
    }

    private static func anchor(at altitude: Double) -> SkyState {
        guard let first = knots.first, altitude > first.altitude else { return knots[0].sky }
        for (lower, upper) in zip(knots, knots.dropFirst()) where altitude <= upper.altitude {
            return lower.sky.mixed(with: upper.sky, smoothstep((altitude - lower.altitude) / (upper.altitude - lower.altitude)))
        }
        return knots[knots.count - 1].sky
    }

    /// Dawn reads a little cooler and rosier than dusk; strongest around sunrise, gone by full
    /// night and by mid-morning.
    private static func dawnWeight(at altitude: Double) -> Double {
        if altitude < blueHourAltitude {
            return smoothstep((altitude - nightAltitude) / (blueHourAltitude - nightAltitude))
        }
        return 1 - smoothstep((altitude - 2) / 10)
    }

    private static let dawnShift: [(a: Double, b: Double)] = [(0, -0.010), (0, -0.010), (0.008, -0.016), (0.012, -0.024), (0, -0.010)]

    private mutating func applyDawnTint(weight: Double) {
        guard weight > 0 else { return }
        for index in colors.indices {
            colors[index].a += Self.dawnShift[index].a * weight
            colors[index].b += Self.dawnShift[index].b * weight
        }
    }

    func mixed(with other: SkyState, _ t: Double) -> SkyState {
        SkyState(
            colors: zip(colors, other.colors).map { $0.mixed(with: $1, t) },
            accent: accent.mixed(with: other.accent, t),
            glassShade: glassShade + (other.glassShade - glassShade) * t
        )
    }

    /// The overlay is defined for full daylight. Below it, each overlay color and the overlay's
    /// glass shade are scaled by how much darker this sky is than the day anchor, so rain at
    /// night is dark slate rather than a grey day pasted over the stars.
    func covered(by overlay: ConditionOverlay) -> SkyState {
        let covered = colors.indices.map { index -> OKLab in
            let base = colors[index]
            let light = Self.dimming(base.l / Self.day.colors[index].l)
            let tone = overlay.colors[index]
            let dimmed = OKLab(l: tone.l * light, a: tone.a * light, b: tone.b * light)
            return base.mixed(with: dimmed, overlay.amount)
        }
        let shade = overlay.glassShade * Self.dimming(glassShade / Self.day.glassShade)
        return SkyState(
            colors: covered,
            accent: accent.mixed(with: overlay.accent, overlay.amount),
            glassShade: glassShade + (shade - glassShade) * overlay.amount
        )
    }

    /// A gamma under 1 keeps a night overlay about as bright as the clear night sky instead of
    /// crushing it to black.
    private static func dimming(_ ratio: Double) -> Double {
        pow(min(max(ratio, 0), 1), 0.6)
    }
}

struct ConditionOverlay {
    var colors: [OKLab]
    var accent: OKLab
    var glassShade: Double
    var amount: Double

    init(colors: [UInt32], accent: UInt32, glassShade: Double, amount: Double) {
        self.colors = colors.map { OKLab(RGB(hex: $0)) }
        self.accent = OKLab(RGB(hex: accent))
        self.glassShade = glassShade
        self.amount = amount
    }

    static let cloudy = ConditionOverlay(colors: [0x2B3442, 0x4C5869, 0x7D8A99, 0xA2ACB7, 0x3B4656], accent: 0xC8D4E2, glassShade: 0.26, amount: 0.6)
    static let partlyCloudy: ConditionOverlay = {
        var overlay = cloudy
        overlay.amount = 0.25
        return overlay
    }()
    static let rain = ConditionOverlay(colors: [0x1C232D, 0x364352, 0x58687A, 0x6E8094, 0x283442], accent: 0xAAD0EE, glassShade: 0.16, amount: 0.85)
    static let storm = ConditionOverlay(colors: [0x15161F, 0x2B2C40, 0x4B4662, 0x645C7E, 0x1F2030], accent: 0xC8B8FF, glassShade: 0.14, amount: 0.9)
    static let snow = ConditionOverlay(colors: [0x3C4757, 0x66748A, 0x9AA8B9, 0xC9D2DC, 0x4F5D72], accent: 0xE6F0FF, glassShade: 0.36, amount: 0.75)
    static let fog = ConditionOverlay(colors: [0x3A3F47, 0x5D646E, 0x8B929B, 0xB1B6BC, 0x4A5058], accent: 0xD7DCE2, glassShade: 0.30, amount: 0.75)
}

extension WeatherScene {
    /// Fixed scenes for `-scene` and the debug menu: golden, day, rain, night, dawn, snow, fog, storm.
    public static let presetNames = ["golden", "day", "rain", "night", "dawn", "snow", "fog", "storm"]

    public static func preset(named name: String) -> WeatherScene? {
        switch name {
        case "golden": WeatherScene(condition: .clear, sunAltitude: 4, isMorning: false)
        case "day": WeatherScene(condition: .clear, sunAltitude: 40, isMorning: true)
        case "rain": WeatherScene(condition: .rain, sunAltitude: 16, isMorning: false)
        case "night": WeatherScene(condition: .clear, sunAltitude: -30, isMorning: false)
        case "dawn": WeatherScene(condition: .clear, sunAltitude: -4, isMorning: true)
        case "snow": WeatherScene(condition: .snow, sunAltitude: 35, isMorning: true)
        case "fog": WeatherScene(condition: .fog, sunAltitude: 35, isMorning: true)
        case "storm": WeatherScene(condition: .storm, sunAltitude: 12, isMorning: false)
        default: nil
        }
    }
}
