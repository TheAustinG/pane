import Foundation
import Testing
@testable import PaneCore

private let blend: TimeInterval = 90
private let glide: TimeInterval = 60
private let t0 = utc("2026-11-01T22:00:00Z")

private func sky(_ condition: ConditionFamily, _ altitude: Double) -> ScenePalette {
    SceneEngine.palette(for: WeatherScene(condition: condition, sunAltitude: altitude, isMorning: false))
}

@Test func newTransitionShowsItsPalette() {
    let golden = sky(.clear, 4)
    let transition = SceneTransition(palette: golden)
    #expect(transition.palette(at: t0) == golden)
    #expect(transition.isSettled(at: t0))
}

@Test func conditionChangeBlendsOverTheSceneBlend() {
    let golden = sky(.clear, 4)
    let rain = sky(.rain, 4)
    var transition = SceneTransition(palette: golden)
    transition.retarget(to: rain, at: t0, blendSeconds: blend, glideSeconds: glide)
    #expect(transition.easing == .easeInOut)
    #expect(transition.duration == blend)
    #expect(transition.palette(at: t0).colorDistance(to: golden) < 1e-9)
    let middle = transition.palette(at: t0.addingTimeInterval(45))
    #expect(middle.colorDistance(to: golden) > 0.05 && middle.colorDistance(to: rain) > 0.05)
    #expect(!transition.isSettled(at: t0.addingTimeInterval(89)))
    #expect(transition.palette(at: t0.addingTimeInterval(90)) == rain)
}

@Test func retargetMidBlendStartsFromWhatIsShown() {
    var transition = SceneTransition(palette: sky(.clear, 4))
    transition.retarget(to: sky(.rain, 4), at: t0, blendSeconds: blend, glideSeconds: glide)
    let switchTime = t0.addingTimeInterval(30)
    let before = transition.palette(at: switchTime)
    transition.retarget(to: sky(.snow, 4), at: switchTime, blendSeconds: blend, glideSeconds: glide)
    #expect(transition.palette(at: switchTime).colorDistance(to: before) < 1e-9)
    #expect(transition.palette(at: switchTime.addingTimeInterval(blend)) == sky(.snow, 4))
}

@Test func sunDriftGlidesLinearly() {
    let start = sky(.clear, -5)
    let next = sky(.clear, -4.8)
    var transition = SceneTransition(palette: start)
    #expect(transition.isDrift(to: next))
    transition.retarget(to: next, at: t0, blendSeconds: blend, glideSeconds: glide)
    #expect(transition.easing == .linear)
    #expect(transition.duration == glide)
    let quarter = transition.palette(at: t0.addingTimeInterval(15))
    let expected = start.interpolated(to: next, fraction: 0.25)
    #expect(quarter.colorDistance(to: expected) < 1e-9)
}

@Test func sunDriftDuringABlendKeepsTheBlendGoing() {
    var transition = SceneTransition(palette: sky(.clear, -5))
    transition.retarget(to: sky(.rain, -5), at: t0, blendSeconds: blend, glideSeconds: glide)
    let tick = t0.addingTimeInterval(60)
    let before = transition.palette(at: tick)
    transition.retarget(to: sky(.rain, -4.8), at: tick, blendSeconds: blend, glideSeconds: glide)
    #expect(transition.start == t0)
    #expect(transition.duration == blend)
    #expect(transition.palette(at: tick).colorDistance(to: before) < 0.02)
}

@Test func particleSwitchCountsAsASceneChange() {
    let night = sky(.clear, -20)
    var transition = SceneTransition(palette: night)
    var stormy = night
    stormy.particles = .storm
    stormy.particleIntensity = 1
    #expect(!transition.isDrift(to: stormy))
    transition.retarget(to: stormy, at: t0, blendSeconds: blend, glideSeconds: glide)
    #expect(transition.duration == blend)
}

/// A whole day of once-a-minute targets, sampled every second, never jumps.
@Test func liveDayNeverJumps() {
    let chicago = GeoPoint(latitude: 41.88, longitude: -87.63)
    let dayStart = utc("2026-11-01T10:00:00Z")
    func target(_ minute: Int) -> ScenePalette {
        let condition: ConditionFamily = minute < 600 ? .clear : .rain
        return SceneEngine.palette(for: SceneEngine.scene(condition: condition, at: dayStart.addingTimeInterval(Double(minute) * 60), location: chicago))
    }
    var transition = SceneTransition(palette: target(0))
    var shown = transition.palette(at: dayStart)
    var worst = 0.0
    for minute in 1..<(18 * 60) {
        let tick = dayStart.addingTimeInterval(Double(minute) * 60)
        transition.retarget(to: target(minute), at: tick, blendSeconds: blend, glideSeconds: glide)
        for second in 0..<60 {
            let now = tick.addingTimeInterval(Double(second))
            let palette = transition.palette(at: now)
            worst = max(worst, palette.colorDistance(to: shown))
            shown = palette
        }
    }
    #expect(worst < 0.01, "largest one-second change \(worst)")
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Test func lightningWaitsTwentyToSixtySeconds() {
    var generator = SplitMix(state: 42)
    var schedule = LightningSchedule()
    var now = t0
    var gaps: [TimeInterval] = []
    for _ in 0..<1000 {
        let next = schedule.nextFlash(after: now, using: &generator)
        gaps.append(next.timeIntervalSince(now))
        schedule.recordFlash(at: next)
        now = next
    }
    #expect(gaps.allSatisfy { $0 >= 20 && $0 <= 60 })
    #expect((gaps.min() ?? 0) < 25 && (gaps.max() ?? 0) > 55, "the whole range is used")
}

@Test func lightningNeverRepeatsWithinTwentySecondsAfterARestart() {
    var generator = SplitMix(state: 7)
    let schedule = LightningSchedule(lastFlash: t0)
    for _ in 0..<200 {
        let next = schedule.nextFlash(after: t0.addingTimeInterval(1), using: &generator)
        #expect(next.timeIntervalSince(t0) >= 20)
    }
}
