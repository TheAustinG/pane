import Foundation

/// The palette the sky is showing while it moves toward its latest target.
///
/// A target close to the previous one (the sun moving for a minute) glides there linearly, so
/// once-a-minute updates chain into continuous motion. A bigger change (a new condition, a debug
/// scene switch) starts an eased blend from whatever is on screen, so nothing ever jumps.
public struct SceneTransition: Sendable {
    public enum Easing: Sendable {
        case linear
        case easeInOut
    }

    public private(set) var from: ScenePalette
    public private(set) var to: ScenePalette
    public private(set) var start: Date
    public private(set) var duration: TimeInterval
    public private(set) var easing: Easing
    private var fromLab: [OKLab]
    private var toLab: [OKLab]

    /// The largest OKLab color change treated as the sky's own drift. A minute of sun motion
    /// moves the palette by under 0.02 at the steepest altitude.
    public static let driftColorLimit = 0.03
    /// The largest change in a particle layer's weight treated as drift.
    public static let driftParticleLimit = 0.2

    public init(palette: ScenePalette) {
        from = palette
        to = palette
        start = .distantPast
        duration = 0
        easing = .linear
        fromLab = Self.lab(palette)
        toLab = fromLab
    }

    public var end: Date {
        start.addingTimeInterval(duration)
    }

    /// Eased progress from `from` to `to`, 0 to 1.
    public func fraction(at date: Date) -> Double {
        guard duration > 0 else { return 1 }
        let t = min(max(date.timeIntervalSince(start) / duration, 0), 1)
        return easing == .linear ? t : smoothstep(t)
    }

    public func isSettled(at date: Date) -> Bool {
        fraction(at: date) >= 1
    }

    public func palette(at date: Date) -> ScenePalette {
        palette(fraction: fraction(at: date))
    }

    public func palette(fraction: Double) -> ScenePalette {
        if fraction >= 1 { return to }
        if fraction <= 0 { return from }
        let mixed = zip(fromLab, toLab).map { $0.mixed(with: $1, fraction).rgb }
        return from.blended(to: to, fraction: fraction, colors: Array(mixed.dropLast()), accent: mixed[mixed.count - 1])
    }

    public func isDrift(to palette: ScenePalette) -> Bool {
        palette.colorDistance(to: to) <= Self.driftColorLimit
            && palette.particleDistance(to: to) <= Self.driftParticleLimit
    }

    public mutating func retarget(to palette: ScenePalette, at date: Date, blendSeconds: TimeInterval, glideSeconds: TimeInterval) {
        guard palette != to else { return }
        let drift = isDrift(to: palette)
        if drift && easing == .easeInOut && !isSettled(at: date) {
            to = palette
            toLab = Self.lab(palette)
            return
        }
        from = self.palette(at: date)
        fromLab = Self.lab(from)
        to = palette
        toLab = Self.lab(palette)
        start = date
        duration = drift ? glideSeconds : blendSeconds
        easing = drift ? .linear : .easeInOut
    }

    private static func lab(_ palette: ScenePalette) -> [OKLab] {
        (palette.colors + [palette.accent]).map(OKLab.init)
    }
}
