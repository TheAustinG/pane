import Testing
@testable import PaneCore

struct BackgroundPolicyCase: Sendable, CustomTestStringConvertible {
    let mode: BackgroundMode
    let light: String
    let sunAltitude: Double
    let isStormActive: Bool
    let expected: BackgroundKind

    var testDescription: String { "\(mode) at \(light)\(isStormActive ? " in a storm" : "")" }
}

private let lights: [(String, Double)] = [("night", -20), ("twilight", -3), ("golden hour", 4), ("day", 30)]

/// Auto shows the photo only with the sun at or above the horizon and storm mode off.
private func expected(_ mode: BackgroundMode, _ light: String, storm: Bool) -> BackgroundKind {
    switch (mode, light, storm) {
    case (.gradient, _, _): .gradient
    case (.photo, _, _): .photo
    case (.auto, "golden hour", false), (.auto, "day", false): .photo
    case (.auto, _, _): .gradient
    }
}

@Suite("Background policy")
struct BackgroundPolicyTests {
    static let table: [BackgroundPolicyCase] = BackgroundMode.allCases.flatMap { mode in
        lights.flatMap { light, altitude in
            [false, true].map { storm in
                BackgroundPolicyCase(mode: mode, light: light, sunAltitude: altitude, isStormActive: storm, expected: expected(mode, light, storm: storm))
            }
        }
    }

    @Test func tableCoversEveryModeLightAndStormState() {
        #expect(Self.table.count == BackgroundMode.allCases.count * lights.count * 2)
    }

    @Test(arguments: table)
    func kind(_ row: BackgroundPolicyCase) {
        for condition in ConditionFamily.allCases {
            for morning in [false, true] {
                let scene = WeatherScene(condition: condition, sunAltitude: row.sunAltitude, isMorning: morning)
                #expect(BackgroundPolicy.kind(mode: row.mode, scene: scene, isStormActive: row.isStormActive) == row.expected)
            }
        }
    }

    @Test(arguments: [(-6.0, BackgroundKind.gradient), (-0.01, .gradient), (0, .photo), (0.01, .photo), (8, .photo)])
    func autoSwitchesAtTheHorizon(altitude: Double, expected: BackgroundKind) {
        let scene = WeatherScene(condition: .clear, sunAltitude: altitude, isMorning: false)
        #expect(BackgroundPolicy.kind(mode: .auto, scene: scene, isStormActive: false) == expected)
        #expect(BackgroundPolicy.kind(mode: .auto, scene: scene, isStormActive: true) == .gradient)
    }

    @Test func autoShowsTheGradientForTheStormPresetOnlyWhileStormModeIsOn() {
        let storm = WeatherScene.preset(named: "storm")!
        #expect(BackgroundPolicy.kind(mode: .auto, scene: storm, isStormActive: false) == .photo)
        #expect(BackgroundPolicy.kind(mode: .auto, scene: storm, isStormActive: true) == .gradient)
    }
}
