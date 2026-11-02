import UIKit

/// Rain streaks from a line emitter above the frame, ported from the Phase 0 spike, where it
/// held 60 fps at 2500 drops while a Canvas dropped frames.
final class RainLayer: ParticleLayer {
    enum Style {
        case rain
        case storm

        var countFactor: Double { self == .storm ? 1.6 : 1 }
        var speed: CGFloat { self == .storm ? 2100 : 1700 }
        var baseLength: CGFloat { self == .storm ? 40 : 30 }
    }

    /// About 14° from vertical, the design's slant.
    static let slant: CGFloat = tan(14 * .pi / 180)
    private static let depthOpacity: [CGFloat] = [0.10, 0.15, 0.22]
    private static let depthWidth: [CGFloat] = [1.0, 1.5, 2.0]
    private static let imageScale: CGFloat = 2
    private static let rainImages = streakImages(baseLength: Style.rain.baseLength)
    private static let stormImages = streakImages(baseLength: Style.storm.baseLength)

    private let emitter = CAEmitterLayer()
    private let style: Style
    private var count = 0
    private var size = CGSize.zero

    var layer: CALayer { emitter }

    init(style: Style) {
        self.style = style
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.renderMode = .unordered
        emitter.birthRate = 0
    }

    func configure(particleCount: Int, reduceMotion: Bool) {
        count = Int(Double(particleCount) * style.countFactor * (reduceMotion ? 0.5 : 1))
        rebuildCells()
    }

    func layout(in bounds: CGRect) {
        emitter.frame = bounds
        guard bounds.size != size else { return }
        size = bounds.size
        let width = bounds.width + bounds.height * Self.slant
        emitter.emitterPosition = CGPoint(x: width / 2, y: -60)
        emitter.emitterSize = CGSize(width: width, height: 1)
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
        let lifetime = Float((size.height + 120) / style.speed)
        let perDepth = Float(count) / 3
        let images = style == .storm ? Self.stormImages : Self.rainImages
        emitter.emitterCells = (0..<3).map { depth in
            let cell = CAEmitterCell()
            cell.contents = images[depth]
            cell.contentsScale = Self.imageScale
            cell.lifetime = lifetime
            cell.birthRate = perDepth / lifetime
            cell.velocity = style.speed + CGFloat(depth) * 200
            cell.velocityRange = 250
            // Measured in the Phase 0 spike: with a line emitter, pi points straight down (a
            // point emitter uses pi / 2).
            cell.emissionLongitude = .pi + atan(Self.slant)
            cell.alphaRange = 0.05
            cell.scaleRange = 0.25
            return cell
        }
    }

    private static func streakImages(baseLength: CGFloat) -> [CGImage?] {
        (0..<3).map { depth in
            let length = baseLength + CGFloat(depth) * 12
            let lineWidth = depthWidth[depth]
            let size = CGSize(width: length * slant + lineWidth * 2, height: length)
            let format = UIGraphicsImageRendererFormat()
            format.scale = imageScale
            format.opaque = false
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                let cg = context.cgContext
                cg.setStrokeColor(UIColor.white.withAlphaComponent(depthOpacity[depth]).cgColor)
                cg.setLineWidth(lineWidth)
                cg.setLineCap(.round)
                cg.move(to: CGPoint(x: size.width - lineWidth, y: 0))
                cg.addLine(to: CGPoint(x: lineWidth, y: size.height))
                cg.strokePath()
            }.cgImage
        }
    }
}
