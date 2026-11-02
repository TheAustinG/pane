import Foundation

/// Render knobs, so a miss on the A15 is a settings change rather than a rewrite. `standard` is
/// the Phase 0 default until the device render check runs.
struct RenderQuality: Hashable, Sendable {
    var name: String
    /// Rain drops on screen at full intensity; other particle kinds scale from it.
    var particleCount: Int
    /// Mesh gradient points per side.
    var meshSize: Int
    /// Resolution of the gradient layer relative to the screen.
    var gradientScale: Double
    var drawingGroup: Bool

    static let light = RenderQuality(name: "light", particleCount: 150, meshSize: 3, gradientScale: 0.5, drawingGroup: true)
    static let standard = RenderQuality(name: "standard", particleCount: 400, meshSize: 3, gradientScale: 0.5, drawingGroup: false)
    static let rich = RenderQuality(name: "rich", particleCount: 1200, meshSize: 4, gradientScale: 1.0, drawingGroup: false)

    static let all = [light, standard, rich]

    static func named(_ name: String?) -> RenderQuality? {
        all.first { $0.name == name }
    }
}
