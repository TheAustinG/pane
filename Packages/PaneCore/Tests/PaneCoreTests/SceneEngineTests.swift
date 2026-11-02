import Foundation
import Testing
@testable import PaneCore

private func palette(_ condition: ConditionFamily, _ altitude: Double, morning: Bool = false) -> ScenePalette {
    SceneEngine.palette(for: WeatherScene(condition: condition, sunAltitude: altitude, isMorning: morning))
}

private func distance(_ palette: ScenePalette, _ hexes: [UInt32]) -> Double {
    zip(palette.colors, hexes).map { $0.distance(to: RGB(hex: $1)) }.max() ?? .infinity
}

private func meanLightness(_ palette: ScenePalette) -> Double {
    palette.colors.map { OKLab($0).l }.reduce(0, +) / Double(palette.colors.count)
}

private enum Design {
    static let night: [UInt32] = [0x050816, 0x111838, 0x232A58, 0x3B356A, 0x0B1230]
    static let blueHour: [UInt32] = [0x151A3E, 0x2E2F66, 0x6B5287, 0xD98F86, 0x223463]
    static let goldenHour: [UInt32] = [0x1E2148, 0x4A3F7A, 0xB9708A, 0xEFA06A, 0x31507E]
    static let day: [UInt32] = [0x123F75, 0x2163AD, 0x5596D4, 0xE4D3A0, 0x1B5597]
    static let rain: [UInt32] = [0x1C232D, 0x364352, 0x58687A, 0x6E8094, 0x283442]
    static let storm: [UInt32] = [0x15161F, 0x2B2C40, 0x4B4662, 0x645C7E, 0x1F2030]
    static let snow: [UInt32] = [0x3C4757, 0x66748A, 0x9AA8B9, 0xC9D2DC, 0x4F5D72]
    static let fog: [UInt32] = [0x3A3F47, 0x5D646E, 0x8B929B, 0xB1B6BC, 0x4A5058]
}

/// The sun moves at most about 0.25° a minute, so a 0.1° step is at least 24 s of real time.
/// Half of OKLab's just-noticeable difference (about 0.02) per step means the palette never
/// visibly jumps even before SkyView glides between minute updates. The steepest stretch, blue
/// hour to golden hour over 4°, peaks near 0.0075.
private let maxStepPerTenthDegree = 0.01

@Test(arguments: ConditionFamily.allCases, [false, true])
func paletteIsContinuousInAltitude(condition: ConditionFamily, morning: Bool) {
    var previous = palette(condition, -20, morning: morning)
    var worstColor = 0.0
    var worstShade = 0.0
    var worstParticles = 0.0
    for step in 1...900 {
        let current = palette(condition, -20 + Double(step) * 0.1, morning: morning)
        #expect(current.colors.count == 5)
        worstColor = max(worstColor, current.colorDistance(to: previous))
        worstShade = max(worstShade, abs(current.glassShade - previous.glassShade))
        worstParticles = max(worstParticles, current.particleDistance(to: previous))
        previous = current
    }
    #expect(worstColor < maxStepPerTenthDegree, "largest color step \(worstColor)")
    #expect(worstShade < 0.005, "largest glass shade step \(worstShade)")
    #expect(worstParticles < 0.03, "largest particle step \(worstParticles)")
}

@Test func anchorsAreReproducedAtTheirAltitudes() {
    let cases: [(Double, [UInt32], UInt32, Double)] = [
        (-30, Design.night, 0xB2BCFF, 0.10),
        (-12, Design.night, 0xB2BCFF, 0.10),
        (-4, Design.blueHour, 0xFFC8B4, 0.16),
        (0, Design.goldenHour, 0xFFC896, 0.20),
        (4, Design.goldenHour, 0xFFC896, 0.20),
        (8, Design.goldenHour, 0xFFC896, 0.20),
        (25, Design.day, 0xFFEAAF, 0.32),
        (60, Design.day, 0xFFEAAF, 0.32),
    ]
    for (altitude, colors, accent, shade) in cases {
        let sky = palette(.clear, altitude)
        #expect(distance(sky, colors) < 0.002, "colors at \(altitude)°")
        #expect(sky.accent.distance(to: RGB(hex: accent)) < 0.002, "accent at \(altitude)°")
        #expect(abs(sky.glassShade - shade) < 1e-9, "glass shade at \(altitude)°")
    }
}

@Test func anchorsSitBetweenTheirNeighbors() {
    let between = palette(.clear, 16.5)
    let golden = palette(.clear, 8)
    let day = palette(.clear, 25)
    #expect(between.colorDistance(to: golden) > 0.03)
    #expect(between.colorDistance(to: day) > 0.03)
    #expect(between.glassShade > golden.glassShade && between.glassShade < day.glassShade)
}

@Test func dawnDiffersOnlySubtlyFromDusk() {
    for altitude in stride(from: -20.0, through: 40, by: 1) {
        let dusk = palette(.clear, altitude, morning: false)
        let dawn = palette(.clear, altitude, morning: true)
        #expect(dawn.colorDistance(to: dusk) < 0.035, "at \(altitude)°")
    }
    #expect(palette(.clear, -4, morning: true).colorDistance(to: palette(.clear, -4)) > 0.005)
    #expect(palette(.clear, -30, morning: true) == palette(.clear, -30))
    #expect(palette(.clear, 30, morning: true) == palette(.clear, 30))
}

@Test(arguments: [ConditionFamily.partlyCloudy, .cloudy, .rain, .storm, .snow, .fog])
func overlaysDarkenWithTheSky(condition: ConditionFamily) {
    let night = palette(condition, -20)
    let day = palette(condition, 35)
    let clearNight = palette(.clear, -20)
    #expect(meanLightness(night) < meanLightness(day) - 0.1)
    for index in 0..<5 {
        #expect(OKLab(night.colors[index]).l < OKLab(day.colors[index]).l, "slot \(index)")
    }
    #expect(abs(meanLightness(night) - meanLightness(clearNight)) < 0.1, "a night overlay stays near the night sky's brightness")
    #expect(night.glassShade <= day.glassShade)
    #expect(night.glassShade >= 0.10)
}

@Test func rainAtNightIsDarkSlate() {
    let rain = palette(.rain, -20)
    for color in rain.colors {
        let lab = OKLab(color)
        #expect(lab.l < 0.4)
        #expect((lab.a * lab.a + lab.b * lab.b).squareRoot() < 0.05, "low chroma: slate, not blue")
    }
}

@Test func overlaysApplyTheirDaylightAmount() {
    let day = palette(.clear, 35)
    let cloudy = palette(.cloudy, 35)
    let partly = palette(.partlyCloudy, 35)
    #expect(partly.colorDistance(to: day) < cloudy.colorDistance(to: day))
    #expect(partly.colorDistance(to: day) > 0.02)
}

@Test func particlesFollowTheCondition() {
    #expect(palette(.clear, 30).particles == .none)
    #expect(palette(.clear, -5).particleIntensity == 0)
    #expect(palette(.clear, -9).particles == .stars)
    #expect(palette(.clear, -9).particleIntensity > 0.2 && palette(.clear, -9).particleIntensity < 0.8)
    #expect(palette(.clear, -20).particles == .stars)
    #expect(palette(.clear, -20).particleIntensity == 1)
    #expect(palette(.partlyCloudy, -20).particles == .stars)
    #expect(abs(palette(.partlyCloudy, -20).particleIntensity - 0.6) < 1e-9)
    #expect(palette(.cloudy, -20).particles == .none)
    #expect(palette(.rain, 30).particles == .rain)
    #expect(palette(.storm, -20).particles == .storm)
    #expect(palette(.snow, 10).particles == .snow)
    #expect(palette(.fog, 30).particles == .fog)
    #expect(palette(.fog, -20).particleIntensity < palette(.fog, 30).particleIntensity)
}

@Test func presetsLandOnTheDesignAnchors() throws {
    func preset(_ name: String) throws -> ScenePalette {
        SceneEngine.palette(for: try #require(WeatherScene.preset(named: name)))
    }
    #expect(distance(try preset("golden"), Design.goldenHour) < 0.002)
    #expect(distance(try preset("day"), Design.day) < 0.002)
    #expect(distance(try preset("night"), Design.night) < 0.002)
    #expect(try preset("night").particles == .stars)
    #expect(try preset("night").particleIntensity == 1)
    #expect(distance(try preset("dawn"), Design.blueHour) < 0.035)
    // An overlay mixes at 75 to 90 percent, so 10 to 25 percent of the day sky remains.
    #expect(distance(try preset("rain"), Design.rain) < 0.06)
    #expect(distance(try preset("storm"), Design.storm) < 0.06)
    #expect(distance(try preset("snow"), Design.snow) < 0.06)
    #expect(distance(try preset("fog"), Design.fog) < 0.06)
    #expect(try preset("rain").particles == .rain)
    #expect(try preset("storm").particles == .storm)
    #expect(try preset("snow").particles == .snow)
    #expect(try preset("fog").particles == .fog)
}

@Test func everyPresetNameResolves() {
    for name in WeatherScene.presetNames {
        #expect(WeatherScene.preset(named: name) != nil, "\(name)")
    }
    #expect(WeatherScene.preset(named: "tornado") == nil)
}

@Test func sceneMarksMorningBeforeSolarNoon() {
    let chicago = GeoPoint(latitude: 41.88, longitude: -87.63)
    let morning = SceneEngine.scene(condition: .rain, at: utc("2026-11-01T15:00:00Z"), location: chicago)
    let evening = SceneEngine.scene(condition: .rain, at: utc("2026-11-01T21:00:00Z"), location: chicago)
    #expect(morning.isMorning)
    #expect(!evening.isMorning)
    #expect(morning.condition == .rain)
    #expect(morning.sunAltitude > 0 && evening.sunAltitude > 0)
}

@Test func interpolationHitsBothEnds() {
    let golden = palette(.clear, 4)
    let rain = palette(.rain, 35)
    #expect(golden.interpolated(to: rain, fraction: 0).colorDistance(to: golden) < 1e-6)
    #expect(golden.interpolated(to: rain, fraction: 1).colorDistance(to: rain) < 1e-6)
    let half = golden.interpolated(to: rain, fraction: 0.5)
    #expect(half.colorDistance(to: golden) > 0.05 && half.colorDistance(to: rain) > 0.05)
    #expect(abs(half.glassShade - (golden.glassShade + rain.glassShade) / 2) < 1e-9)
}

@Test func interpolationCrossfadesParticleKinds() {
    let night = palette(.clear, -20)
    let rain = palette(.rain, -20)
    #expect(night.interpolated(to: rain, fraction: 0.25).particles == .stars)
    #expect(abs(night.interpolated(to: rain, fraction: 0.25).particleIntensity - 0.5) < 1e-9)
    #expect(night.interpolated(to: rain, fraction: 0.75).particles == .rain)
    #expect(abs(night.interpolated(to: rain, fraction: 0.75).particleIntensity - 0.5) < 1e-9)
    let dusk = palette(.clear, -8)
    #expect(abs(dusk.interpolated(to: night, fraction: 0.5).particleIntensity - (dusk.particleIntensity + 1) / 2) < 1e-9)
}

@Test func oklabRoundTripsSRGB() {
    for hex: UInt32 in [0x000000, 0xFFFFFF, 0x050816, 0xEFA06A, 0x5596D4, 0x808080] {
        let rgb = RGB(hex: hex)
        let back = OKLab(rgb).rgb
        #expect(abs(back.red - rgb.red) < 1e-6 && abs(back.green - rgb.green) < 1e-6 && abs(back.blue - rgb.blue) < 1e-6)
    }
    #expect(abs(OKLab(RGB(hex: 0xFFFFFF)).l - 1) < 1e-4)
}
