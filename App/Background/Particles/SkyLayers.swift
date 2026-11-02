import PaneCore
import UIKit

@MainActor
final class SnowLayer: ParticleLayer {
    private static let depthScale: [CGFloat] = [0.3, 0.45, 0.65]
    private static let depthSpeed: [CGFloat] = [40, 60, 85]
    private static let depthAlpha: [Float] = [0.5, 0.68, 0.85]

    private let emitter = CAEmitterLayer()
    private var count = 0
    private var size = CGSize.zero

    var layer: CALayer { emitter }

    init() {
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.renderMode = .unordered
        emitter.birthRate = 0
    }

    func configure(particleCount: Int, reduceMotion: Bool) {
        count = Int(Double(particleCount) * 0.7 * (reduceMotion ? 0.5 : 1))
        rebuildCells()
    }

    func layout(in bounds: CGRect) {
        emitter.frame = bounds
        guard bounds.size != size else { return }
        size = bounds.size
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -20)
        emitter.emitterSize = CGSize(width: bounds.width * 1.3, height: 1)
        rebuildCells()
    }

    func setWeight(_ weight: Double, duration: TimeInterval) {
        emitter.animateFloat("birthRate", to: Float(weight), duration: duration)
    }

    private func rebuildCells() {
        guard size.height > 0, count > 0 else {
            emitter.emitterCells = nil
            return
        }
        let travel = size.height + 60
        emitter.emitterCells = (0..<3).map { depth in
            let speed = Self.depthSpeed[depth]
            let onScreen = Float(travel / speed)
            let cell = CAEmitterCell()
            cell.contents = ParticleImages.softDot
            cell.contentsScale = ParticleImages.scale
            cell.lifetime = Float(travel / (speed * 0.7))
            cell.birthRate = Float(count) / 3 / onScreen
            cell.velocity = speed
            cell.velocityRange = speed * 0.3
            cell.emissionLongitude = .pi
            cell.emissionRange = 0.35
            cell.xAcceleration = 3
            cell.scale = Self.depthScale[depth]
            cell.scaleRange = Self.depthScale[depth] * 0.3
            cell.alphaRange = 0.15
            cell.color = UIColor(white: 1, alpha: CGFloat(Self.depthAlpha[depth])).cgColor
            return cell
        }
    }
}

/// A fixed field of stars, brighter and denser toward the top of the frame, with a slow twinkle
/// on some of them. Core Animation runs the twinkle, so the field costs nothing per frame.
@MainActor
final class StarLayer: ParticleLayer {
    private let container = CALayer()
    private var count = 0
    private var twinkles = true
    private var size = CGSize.zero

    var layer: CALayer { container }

    init() {
        container.opacity = 0
    }

    func configure(particleCount: Int, reduceMotion: Bool) {
        count = min(max(particleCount / 4, 30), 160) / (reduceMotion ? 2 : 1)
        twinkles = !reduceMotion
        rebuild()
    }

    func layout(in bounds: CGRect) {
        container.frame = bounds
        guard bounds.size != size else { return }
        size = bounds.size
        rebuild()
    }

    func setWeight(_ weight: Double, duration: TimeInterval) {
        container.animateFloat("opacity", to: Float(weight), duration: duration)
    }

    private func rebuild() {
        container.sublayers = nil
        guard size.height > 0, count > 0 else { return }
        var random = SplitMix(seed: 0x57A25)
        for _ in 0..<count {
            let star = CALayer()
            let diameter = 3 + random.unit() * 3.5
            let height = pow(random.unit(), 1.4) * 0.6
            star.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            star.position = CGPoint(x: random.unit() * size.width, y: height * size.height)
            star.contents = ParticleImages.star
            let brightness = Float(0.4 + random.unit() * 0.55) * Float(1 - height * 0.5)
            star.opacity = brightness
            if twinkles, random.unit() < 0.3 {
                let twinkle = CABasicAnimation(keyPath: "opacity")
                twinkle.fromValue = brightness
                twinkle.toValue = brightness * 0.3
                twinkle.duration = 2.5 + random.unit() * 4
                twinkle.autoreverses = true
                twinkle.repeatCount = .infinity
                twinkle.timeOffset = random.unit() * 6
                twinkle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                star.add(twinkle, forKey: "twinkle")
            }
            container.addSublayer(star)
        }
    }
}

@MainActor
final class FogLayer: ParticleLayer {
    private let container = CALayer()
    private var bandCount = 5
    private var drifts = true
    private var size = CGSize.zero

    var layer: CALayer { container }

    init() {
        container.opacity = 0
    }

    func configure(particleCount: Int, reduceMotion: Bool) {
        bandCount = particleCount >= 400 ? 6 : 4
        drifts = !reduceMotion
        rebuild()
    }

    func layout(in bounds: CGRect) {
        container.frame = bounds
        guard bounds.size != size else { return }
        size = bounds.size
        rebuild()
    }

    func setWeight(_ weight: Double, duration: TimeInterval) {
        container.animateFloat("opacity", to: Float(weight), duration: duration)
    }

    private func rebuild() {
        container.sublayers = nil
        guard size.height > 0 else { return }
        var random = SplitMix(seed: 0xF06)
        for band in 0..<bandCount {
            let layer = CALayer()
            let width = size.width * (0.8 + random.unit() * 0.6)
            let height = size.height * (0.24 + random.unit() * 0.14)
            let y = size.height * (0.22 + CGFloat(band) / CGFloat(max(bandCount - 1, 1)) * 0.62)
            layer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            layer.position = CGPoint(x: size.width * (0.2 + random.unit() * 0.6), y: y)
            layer.contents = ParticleImages.mist
            layer.opacity = Float(0.12 + random.unit() * 0.08)
            if drifts {
                let travel = 140 + random.unit() * 160
                let drift = CABasicAnimation(keyPath: "position.x")
                drift.byValue = random.unit() < 0.5 ? travel : -travel
                drift.duration = 70 + random.unit() * 50
                drift.autoreverses = true
                drift.repeatCount = .infinity
                drift.timeOffset = random.unit() * drift.duration
                drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(drift, forKey: "drift")
            }
            container.addSublayer(layer)
        }
    }
}

@MainActor
final class LightningFlash {
    let layer = CALayer()
    private var schedule = LightningSchedule()
    private var task: Task<Void, Never>?
    private var peak: Float = 0

    init() {
        layer.backgroundColor = UIColor.white.cgColor
        layer.opacity = 0
    }

    func update(stormWeight: Double, enabled: Bool) {
        peak = Float(LightningSchedule.flashOpacity * min(max(stormWeight, 0), 1))
        let runs = enabled && stormWeight > 0.05
        if runs, task == nil {
            task = Task { [weak self] in
                while !Task.isCancelled {
                    guard let delay = self?.delayToNextFlash() else { return }
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, let self else { return }
                    self.flash()
                }
            }
        } else if !runs {
            task?.cancel()
            task = nil
        }
    }

    private func delayToNextFlash() -> TimeInterval {
        let now = Date.now
        return schedule.nextFlash(after: now).timeIntervalSince(now)
    }

    private func flash() {
        schedule.recordFlash(at: .now)
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, peak, peak * 0.5, peak * 0.85, 0]
        animation.keyTimes = [0, 0.12, 0.4, 0.55, 1]
        animation.duration = LightningSchedule.flashDuration
        layer.add(animation, forKey: "flash")
    }
}

@MainActor
enum ParticleImages {
    static let scale: CGFloat = 2

    /// A white disc fading to clear at its edge: snowflakes.
    static let softDot = radialImage(diameter: 32, stops: [(0, 1), (0.35, 0.55), (1, 0)])
    /// A crisp core with a short glow, so a star a few points wide still reads.
    static let star = radialImage(diameter: 16, stops: [(0, 1), (0.45, 0.9), (0.7, 0.3), (1, 0)])
    /// A near-Gaussian falloff. Stretched wide, it reads as a blurred band of mist.
    static let mist = radialImage(diameter: 64, stops: [(0, 1), (0.2, 0.85), (0.4, 0.55), (0.6, 0.27), (0.8, 0.08), (1, 0)])

    private static func radialImage(diameter: CGFloat, stops: [(location: CGFloat, alpha: CGFloat)]) -> CGImage? {
        let size = CGSize(width: diameter, height: diameter)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = stops.map { UIColor.white.withAlphaComponent($0.alpha).cgColor }
            let locations = stops.map(\.location)
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: diameter / 2, options: [])
        }.cgImage
    }
}

struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func unit() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}
