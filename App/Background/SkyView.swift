import PaneCore
import SwiftUI

/// The live background: the scene's mesh gradient drifting slowly, plus its particle layer.
/// Blends to a new `target` palette over `Theme.Motion.sceneBlendSeconds`.
struct SkyView: View {
    let target: ScenePalette
    let quality: RenderQuality
    var particlesEnabled = true

    @State private var transition: SceneTransition
    @State private var particleFadeEnd = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Once-a-minute time-of-day updates glide over a minute, so they chain into steady motion.
    private static let glideSeconds: TimeInterval = 60

    init(target: ScenePalette, quality: RenderQuality, particlesEnabled: Bool = true) {
        self.target = target
        self.quality = quality
        self.particlesEnabled = particlesEnabled
        _transition = State(initialValue: SceneTransition(palette: target))
    }

    var body: some View {
        ZStack {
            SkyGradient(transition: transition, quality: quality, drifts: !reduceMotion)
            ParticleField(
                palette: particlesEnabled ? transition.to : transition.to.withoutParticles,
                transitionEnd: max(transition.end, particleFadeEnd),
                particleCount: quality.particleCount,
                reduceMotion: reduceMotion
            )
            SkyVignette()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: particlesEnabled) {
            particleFadeEnd = .now.addingTimeInterval(Theme.Motion.nightDimSeconds)
        }
        .onChange(of: target) { _, newTarget in
            transition.retarget(
                to: newTarget,
                at: .now,
                blendSeconds: Theme.Motion.sceneBlendSeconds,
                glideSeconds: Self.glideSeconds
            )
        }
    }
}

private extension ScenePalette {
    var withoutParticles: ScenePalette {
        var palette = self
        palette.particleIntensity = 0
        return palette
    }
}
