import PaneCore
import SwiftUI

/// Mesh geometry and colors for the sky. Caches what does not change between frames so a
/// settled sky only rebuilds its drifting points.
@MainActor
final class SkyMesh {
    struct Frame {
        let size: Int
        let points: [SIMD2<Float>]
        let colors: [Color.Resolved]
    }

    private struct ColorKey: Equatable {
        let size: Int
        let start: Date
        let target: ScenePalette
        let step: Int
    }

    private var size = 0
    private var basePoints: [SIMD2<Float>] = []
    private var drift: [Drift] = []
    private var colorKey: ColorKey?
    private var colors: [Color.Resolved] = []

    /// Blend progress is quantized to this many steps. A 60 s glide then updates the colors
    /// every 30 ms, far below a visible change, instead of on every frame.
    private static let blendSteps = 2000

    func frame(size: Int, transition: SceneTransition, date: Date, drifts: Bool) -> Frame {
        prepare(size: size)
        let step = Int((transition.fraction(at: date) * Double(Self.blendSteps)).rounded())
        let key = ColorKey(size: size, start: transition.start, target: transition.to, step: step)
        if key != colorKey {
            colorKey = key
            colors = Self.meshColors(transition.palette(fraction: Double(step) / Double(Self.blendSteps)), size: size)
        }
        return Frame(size: size, points: drifts ? driftedPoints(at: date) : basePoints, colors: colors)
    }

    private func prepare(size: Int) {
        guard size != self.size else { return }
        self.size = size
        colorKey = nil
        basePoints = []
        drift = []
        basePoints.reserveCapacity(size * size)
        drift.reserveCapacity(size * size)
        for row in 0..<size {
            for col in 0..<size {
                let u = Self.nodeCoordinate(col, of: size)
                let v = Self.nodeCoordinate(row, of: size)
                basePoints.append(SIMD2(u, v) + Self.warp.sample(u: u, v: v))
                drift.append(Drift(index: row * size + col, movesX: col > 0 && col < size - 1, movesY: row > 0 && row < size - 1))
            }
        }
    }

    private func driftedPoints(at date: Date) -> [SIMD2<Float>] {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Drift.cycle)
        var points = basePoints
        for index in points.indices {
            points[index] += drift[index].offset(at: t)
        }
        return points
    }

    /// The design preview's mesh layout (PreviewSky), as offsets from a regular 3x3 grid.
    /// Other sizes sample it bilinearly so every size keeps the same composition.
    private static let warp = Grid3<SIMD2<Float>>([
        [0, 0], [0.05, 0], [0, 0],
        [0, 0.02], [0.12, -0.06], [0, -0.02],
        [0, 0], [-0.08, 0], [0, 0],
    ])

    /// The five scene colors laid out like PreviewSky: top left, top right, center, low glow
    /// bottom left, bottom right, with sRGB mixes in between to match the approved stills.
    static func meshColors(_ palette: ScenePalette, size: Int) -> [Color.Resolved] {
        let c = palette.colors.map { SIMD3<Float>(Float($0.red), Float($0.green), Float($0.blue)) }
        let field = Grid3<SIMD3<Float>>([
            c[0], mix(c[0], c[1], 0.5), c[1],
            mix(c[0], c[3], 0.35), c[2], mix(c[1], c[4], 0.5),
            c[3], mix(c[3], c[4], 0.5), c[4],
        ])
        var result: [Color.Resolved] = []
        result.reserveCapacity(size * size)
        for row in 0..<size {
            for col in 0..<size {
                let rgb = field.sample(u: nodeCoordinate(col, of: size), v: nodeCoordinate(row, of: size))
                result.append(Color.Resolved(red: rgb.x, green: rgb.y, blue: rgb.z))
            }
        }
        return result
    }

    /// Where a node sits in the 3x3 layout, 0 to 1. An even mesh has no center node, and spread
    /// evenly its interior nodes would wash the center glow into a broad plateau, so they
    /// cluster around the center instead: the 4x4 mesh then matches the 3x3 stills and only
    /// adds freedom to the drift. They stay far enough apart that drift never folds the mesh.
    static func nodeCoordinate(_ index: Int, of size: Int) -> Float {
        let t = Float(index) / Float(size - 1)
        guard size % 2 == 0, index > 0, index < size - 1 else { return t }
        return 0.5 + (t - 0.5) * 0.45
    }

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }
}

/// One mesh point's slow wander. Edge points slide along their edge and corners stay put, so the
/// mesh always covers the frame.
private struct Drift {
    let amplitude: SIMD2<Float>
    let phase: SIMD4<Double>

    init(index: Int, movesX: Bool, movesY: Bool) {
        let interior = movesX && movesY
        amplitude = SIMD2(movesX ? (interior ? 0.055 : 0.04) : 0, movesY ? (interior ? 0.045 : 0.035) : 0)
        let seed = Double(index)
        phase = SIMD4(seed * 1.7, seed * 2.3 + 1, seed * 0.9 + 2, seed * 3.1 + 3)
    }

    static let angular: SIMD4<Double> = {
        let periods = Theme.Motion.driftPeriods
        return 2 * .pi / SIMD4(periods[0], periods[1], periods[2], periods[3])
    }()

    /// A common multiple of every period, so wrapping time keeps each sine continuous while
    /// staying small enough for full Double precision.
    static let cycle: Double = Theme.Motion.driftPeriods.reduce(1, *)

    func offset(at t: Double) -> SIMD2<Float> {
        guard amplitude != .zero else { return .zero }
        let w = Self.angular * t + phase
        let x = 0.62 * sin(w[0]) + 0.38 * sin(w[2])
        let y = 0.62 * sin(w[1]) + 0.38 * sin(w[3])
        return amplitude * SIMD2(Float(x), Float(y))
    }
}

/// Values on a 3x3 grid over the unit square, sampled bilinearly.
private struct Grid3<Value: SIMD> where Value.Scalar == Float {
    let values: [Value]

    init(_ values: [Value]) {
        self.values = values
    }

    func sample(u: Float, v: Float) -> Value {
        let gx = min(max(u, 0), 1) * 2
        let gy = min(max(v, 0), 1) * 2
        let x0 = min(1, Int(gx))
        let y0 = min(1, Int(gy))
        let fx = gx - Float(x0)
        let fy = gy - Float(y0)
        let top = values[y0 * 3 + x0] + (values[y0 * 3 + x0 + 1] - values[y0 * 3 + x0]) * fx
        let bottom = values[(y0 + 1) * 3 + x0] + (values[(y0 + 1) * 3 + x0 + 1] - values[(y0 + 1) * 3 + x0]) * fx
        return top + (bottom - top) * fy
    }
}
