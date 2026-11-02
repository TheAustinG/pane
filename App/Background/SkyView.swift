import PaneCore
import SwiftUI

/// The live background: the scene's mesh gradient drifting slowly, plus its particle layer.
/// Blends to a new `target` palette over `Theme.Motion.sceneBlendSeconds`.
struct SkyView: View {
    let target: ScenePalette
    let quality: RenderQuality
    var particlesEnabled = true

    @State private var transition: SceneTransition
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
            if particlesEnabled {
                ParticleField(
                    palette: transition.to,
                    transitionEnd: transition.end,
                    particleCount: quality.particleCount,
                    reduceMotion: reduceMotion
                )
            }
            SkyVignette()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
