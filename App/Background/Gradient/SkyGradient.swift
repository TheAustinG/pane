import PaneCore
import SwiftUI

/// The sky's mesh gradient, drifting on one animation timeline and following the transition.
struct SkyGradient: View {
    let transition: SceneTransition
    let quality: RenderQuality
    let drifts: Bool

    @State private var mesh = SkyMesh()

    var body: some View {
        let scale = min(max(quality.gradientScale, 0.1), 1)
        if scale < 0.999 {
            GeometryReader { geometry in
                meshTimeline
                    .frame(width: geometry.size.width * scale, height: geometry.size.height * scale)
                    // Rasterizes at the reduced size so scaleEffect stretches a bitmap instead of
                    // redrawing the mesh at full size.
                    .drawingGroup()
                    .scaleEffect(1 / scale, anchor: .topLeading)
            }
        } else if quality.drawingGroup {
            meshTimeline.drawingGroup()
        } else {
            meshTimeline
        }
    }

    private var meshTimeline: some View {
        let size = min(max(quality.meshSize, 2), 6)
        // Without drift only a scene blend moves, and a 1 s step of a 90 s blend is invisible.
        return TimelineView(.animation(minimumInterval: drifts ? nil : 1)) { context in
            let frame = mesh.frame(size: size, transition: transition, date: context.date, drifts: drifts)
            MeshGradient(width: frame.size, height: frame.size, points: frame.points, resolvedColors: frame.colors)
        }
    }
}

/// The soft darkening toward the corners from the design preview.
struct SkyVignette: View {
    var body: some View {
        RadialGradient(
            colors: [.clear, .black.opacity(0.28)],
            center: UnitPoint(x: 0.5, y: 0.4),
            startRadius: 700,
            endRadius: 1300
        )
    }
}
