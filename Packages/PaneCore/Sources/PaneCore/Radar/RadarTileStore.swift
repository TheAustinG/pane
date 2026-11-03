import Foundation
import Synchronization

/// Tile image bytes by frame, readable from any thread: MapKit draws overlays off the main thread.
public final class RadarTileStore: Sendable {
    private struct Key: Hashable {
        let frame: String
        let tile: TileCoordinate
    }

    private let tiles = Mutex<[Key: Data]>([:])

    public init() {}

    public func data(frame: String, tile: TileCoordinate) -> Data? {
        tiles.withLock { $0[Key(frame: frame, tile: tile)] }
    }

    public func contains(frame: String, tile: TileCoordinate) -> Bool {
        data(frame: frame, tile: tile) != nil
    }

    public func insert(_ data: Data, frame: String, tile: TileCoordinate) {
        tiles.withLock { $0[Key(frame: frame, tile: tile)] = data }
    }

    /// Drops every frame not in `frames`.
    public func keep(frames: Set<String>) {
        tiles.withLock { $0 = $0.filter { frames.contains($0.key.frame) } }
    }
}
