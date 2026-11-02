#if DEBUG
import SwiftUI

/// A still frame of a scene for the design preview: the mesh at rest plus a static hint of its
/// particles. Motion belongs to the real background renderer.
struct PreviewSky: View {
    let scene: ScenePreset
    var particles = true

    var body: some View {
        ZStack {
            MeshGradient(width: 3, height: 3, points: Self.points, colors: meshColors)
            if particles {
                ParticleHint(kind: scene.particles)
            }
            RadialGradient(
                colors: [.clear, .black.opacity(0.28)],
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: 700,
                endRadius: 1300
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.55, 0], [1, 0],
        [0, 0.52], [0.62, 0.44], [1, 0.48],
        [0, 1], [0.42, 1], [1, 1],
    ]

    private var meshColors: [Color] {
        let c = scene.colors
        return [
            Color(hex: c[0]), Color(hex: mix(c[0], c[1], 0.5)), Color(hex: c[1]),
            Color(hex: mix(c[0], c[3], 0.35)), Color(hex: c[2]), Color(hex: mix(c[1], c[4], 0.5)),
            Color(hex: c[3]), Color(hex: mix(c[3], c[4], 0.5)), Color(hex: c[4]),
        ]
    }

    private func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF)
            let y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

private struct ParticleHint: View {
    let kind: ScenePreset.Particles

    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 7
            func unit() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(1 << 31)
            }
            switch kind {
            case .none:
                break
            case .stars:
                for _ in 0..<70 {
                    let r = 1 + unit() * 1.6
                    let rect = CGRect(x: unit() * size.width, y: unit() * size.height * 0.55, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.35 + unit() * 0.55)))
                }
            case .rain, .storm:
                let count = kind == .storm ? 260 : 180
                let slant: CGFloat = 0.25
                for _ in 0..<count {
                    let x = unit() * (size.width + 200) - 100
                    let y = unit() * size.height
                    let length = 40 + unit() * 50
                    var streak = Path()
                    streak.move(to: CGPoint(x: x, y: y))
                    streak.addLine(to: CGPoint(x: x - length * slant, y: y + length))
                    context.stroke(streak, with: .color(.white.opacity(0.10 + unit() * 0.12)), lineWidth: 1.4)
                }
            case .snow:
                for _ in 0..<220 {
                    let r = 2 + unit() * 3.5
                    let rect = CGRect(x: unit() * size.width, y: unit() * size.height, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.30 + unit() * 0.45)))
                }
            case .fog:
                context.addFilter(.blur(radius: 60))
                for band in 0..<5 {
                    let y = size.height * (0.25 + CGFloat(band) * 0.15)
                    let rect = CGRect(x: -200 + unit() * 300, y: y, width: size.width * (0.7 + unit() * 0.5), height: 90)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.16)))
                }
            }
        }
    }
}
#endif
