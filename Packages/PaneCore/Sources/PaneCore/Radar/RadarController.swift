import Foundation
import Observation

public enum RadarPhase: Hashable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
}

/// Loads radar frames and tiles for the viewport into `store` while `run()` runs. The app sets
/// `viewport`, draws `tiles` of a ready frame from `store`, and redraws when `revision` changes.
@MainActor
@Observable
public final class RadarController {
    public private(set) var phase: RadarPhase = .idle
    /// Who to credit on screen, for example "Iowa Environmental Mesonet".
    public private(set) var credit: String?
    /// Oldest first.
    public private(set) var frames: [RadarFrame] = []
    /// Frames whose tiles have all arrived; the loop plays only these.
    public private(set) var readyFrameIDs: Set<String> = []
    public private(set) var zoom = 0
    public private(set) var tiles: [TileCoordinate] = []
    /// Bumps whenever tiles arrive.
    public private(set) var revision = 0
    public var viewport: RadarViewport? {
        didSet {
            guard viewport != oldValue else { return }
            layoutTiles()
        }
    }

    public let store = RadarTileStore()

    @ObservationIgnored private let session: URLSession
    private static let zoomRange = 6...10
    private static let base = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/"

    public init(viewport: RadarViewport? = nil, session: URLSession = .shared) {
        self.session = session
        self.viewport = viewport
        layoutTiles()
    }

    /// The frames the loop can play, oldest first.
    public var readyFrames: [RadarFrame] {
        frames.filter { readyFrameIDs.contains($0.id) }
    }

    /// Runs until the calling task is cancelled.
    public func run() async {
        guard viewport != nil else { return }
        phase = .loading
        credit = "Iowa Environmental Mesonet"
        let step = 300.0
        let latest = (Date.now.timeIntervalSince1970 / step).rounded(.down) * step
        frames = stride(from: 55, through: 0, by: -5).map { minutes in
            let layer = minutes == 0 ? "nexrad-n0q-900913" : String(format: "nexrad-n0q-900913-m%02dm", minutes)
            return RadarFrame(id: layer, time: Date(timeIntervalSince1970: latest - Double(minutes) * 60))
        }
        for frame in frames.reversed() {
            for tile in tiles where !store.contains(frame: frame.id, tile: tile) {
                guard !Task.isCancelled else { return }
                let url = URL(string: "\(Self.base)\(frame.id)/\(tile.z)/\(tile.x)/\(tile.y).png")!
                if let (data, _) = try? await session.data(from: url) {
                    store.insert(data, frame: frame.id, tile: tile)
                    revision += 1
                }
            }
            readyFrameIDs.insert(frame.id)
            phase = .ready
        }
    }

    private func layoutTiles() {
        guard let viewport else {
            tiles = []
            return
        }
        zoom = TileMath.zoom(for: viewport, in: Self.zoomRange)
        tiles = TileMath.tiles(covering: viewport.bounds, z: zoom)
    }
}
