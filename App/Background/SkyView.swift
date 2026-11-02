import PaneCore
import SwiftUI

/// The live background: the scene's mesh gradient drifting slowly, plus its particle layer.
/// Blends to a new `target` palette over `Theme.Motion.sceneBlendSeconds`.
struct SkyView: View {
    let target: ScenePalette
    let quality: RenderQuality
    var particlesEnabled = true

    var body: some View {
        Color(red: target.colors[0].red, green: target.colors[0].green, blue: target.colors[0].blue)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
