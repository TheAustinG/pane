import PaneCore
import SwiftUI

/// The dashboard and Settings background: the gradient sky or a blurred photo, by
/// `BackgroundPolicy`, crossfading when either changes.
struct BackgroundView: View {
    let kind: BackgroundKind
    let photo: PhotoKey
    let palette: ScenePalette
    let quality: RenderQuality
    var particlesEnabled = true
    var animates = true

    var body: some View {
        SkyView(target: palette, quality: quality, particlesEnabled: particlesEnabled, animates: animates)
            .overlay {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("Background")
                    .accessibilityValue(kind == .photo ? "photo \(photo.name)" : "gradient")
                    .accessibilityIdentifier("background.kind")
            }
    }
}
