import PaneCore
import SwiftUI
import UIKit

/// The sky's particle layers: stars, fog, snow, rain and storm, each a Core Animation layer the
/// render server animates, so falling rain costs the main thread nothing per frame. A change of
/// scene fades the layers over the scene transition.
struct ParticleField: UIViewRepresentable {
    let palette: ScenePalette
    let transitionEnd: Date
    let particleCount: Int
    let reduceMotion: Bool

    func makeUIView(context: Context) -> ParticleFieldView {
        ParticleFieldView()
    }

    func updateUIView(_ view: ParticleFieldView, context: Context) {
        var weights: [ParticleKind: Double] = [:]
        for kind in ParticleKind.allCases {
            weights[kind] = palette.particleWeight(for: kind)
        }
        view.update(
            weights: weights,
            duration: max(0, transitionEnd.timeIntervalSinceNow),
            particleCount: particleCount,
            reduceMotion: reduceMotion
        )
    }
}

final class ParticleFieldView: UIView {
    private static let order: [ParticleKind] = [.stars, .fog, .snow, .rain, .storm]
    private static let appearSeconds: TimeInterval = 1.5
    /// Long enough for the slowest snowflake born at the end of a fade to leave the frame.
    private static let hideDelay: TimeInterval = 45

    private var layers: [ParticleKind: any ParticleLayer] = [:]
    private var targetWeights: [ParticleKind: Double] = [:]
    private var hideTasks: [ParticleKind: Task<Void, Never>] = [:]
    private var particleCount = 0
    private var reduceMotion = false
    private var hasUpdated = false
    private var stormWeight = 0.0
    private let lightning = LightningFlash()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        lightning.layer.zPosition = CGFloat(Self.order.count)
        layer.addSublayer(lightning.layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func update(weights: [ParticleKind: Double], duration: TimeInterval, particleCount: Int, reduceMotion: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if particleCount != self.particleCount || reduceMotion != self.reduceMotion {
            self.particleCount = particleCount
            self.reduceMotion = reduceMotion
            for particleLayer in layers.values {
                particleLayer.configure(particleCount: particleCount, reduceMotion: reduceMotion)
            }
        }
        let fade = hasUpdated ? duration : 0
        for (index, kind) in Self.order.enumerated() {
            let weight = weights[kind] ?? 0
            if layers[kind] == nil, weight > 0 {
                let particleLayer = Self.makeLayer(kind)
                particleLayer.layer.zPosition = CGFloat(index)
                particleLayer.configure(particleCount: particleCount, reduceMotion: reduceMotion)
                particleLayer.layout(in: bounds)
                layer.addSublayer(particleLayer.layer)
                layers[kind] = particleLayer
            }
            guard let particleLayer = layers[kind], targetWeights[kind] != weight else { continue }
            targetWeights[kind] = weight
            hideTasks[kind]?.cancel()
            particleLayer.layer.isHidden = false
            particleLayer.setWeight(weight, duration: fade)
            if weight == 0 {
                hideWhenFaded(kind, after: fade + Self.hideDelay)
            }
        }
        if !hasUpdated {
            hasUpdated = true
            layer.fade(from: 0, to: 1, duration: Self.appearSeconds)
        }
        stormWeight = weights[.storm] ?? 0
        updateLightning()
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for particleLayer in layers.values {
            particleLayer.layout(in: bounds)
        }
        lightning.layer.frame = bounds
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateLightning()
    }

    /// A faded-out layer keeps its twinkles and drifts running unless it is hidden.
    private func hideWhenFaded(_ kind: ParticleKind, after delay: TimeInterval) {
        hideTasks[kind] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.targetWeights[kind] == 0 else { return }
            self.layers[kind]?.layer.isHidden = true
        }
    }

    private func updateLightning() {
        lightning.update(stormWeight: stormWeight, enabled: window != nil && !reduceMotion)
    }

    private static func makeLayer(_ kind: ParticleKind) -> any ParticleLayer {
        switch kind {
        case .stars: StarLayer()
        case .fog: FogLayer()
        case .snow: SnowLayer()
        case .storm: RainLayer(style: .storm)
        case .rain, .none: RainLayer(style: .rain)
        }
    }
}

@MainActor
protocol ParticleLayer: AnyObject {
    var layer: CALayer { get }
    func configure(particleCount: Int, reduceMotion: Bool)
    func layout(in bounds: CGRect)
    func setWeight(_ weight: Double, duration: TimeInterval)
}

extension CALayer {
    /// Moves a Float property such as opacity or an emitter's birthRate to `value` over
    /// `duration`, starting from what is on screen now so an interrupted fade never jumps.
    func animateFloat(_ keyPath: String, to value: Float, duration: TimeInterval) {
        let shown = (presentation()?.value(forKeyPath: keyPath) as? NSNumber)?.floatValue
            ?? (self.value(forKeyPath: keyPath) as? NSNumber)?.floatValue
            ?? value
        removeAnimation(forKey: keyPath)
        setValue(NSNumber(value: value), forKeyPath: keyPath)
        guard duration > 0, abs(shown - value) > 0.0001 else { return }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = shown
        animation.toValue = value
        animation.duration = duration
        add(animation, forKey: keyPath)
    }

    func fade(from start: Float, to end: Float, duration: TimeInterval) {
        opacity = end
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = start
        animation.toValue = end
        animation.duration = duration
        add(animation, forKey: "appear")
    }
}
