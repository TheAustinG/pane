import Foundation
import Synchronization

/// Tile PNG bytes by frame, readable from any thread: MapKit draws overlays off the main thread.
/// Only encoded bytes are kept; a decoded tile would be about 256 KB. Known empty tiles store
/// nothing, so the renderer draws nothing there.
public final class RadarTileStore: Sendable {
    private struct Key: Hashable {
        let frame: String
        let tile: TileCoordinate
    }

    private struct Contents {
        var images: [Key: Data] = [:]
        var empty: Set<Key> = []
    }

    private let contents = Mutex(Contents())

    public init() {}

    public func data(frame: String, tile: TileCoordinate) -> Data? {
        contents.withLock { $0.images[Key(frame: frame, tile: tile)] }
    }

    /// Whether image bytes are stored for the tile.
    public func contains(frame: String, tile: TileCoordinate) -> Bool {
        data(frame: frame, tile: tile) != nil
    }

    /// Stored or known empty: nothing is left to fetch for the tile.
    public func isResolved(frame: String, tile: TileCoordinate) -> Bool {
        let key = Key(frame: frame, tile: tile)
        return contents.withLock { $0.images[key] != nil || $0.empty.contains(key) }
    }

    public func insert(_ data: Data, frame: String, tile: TileCoordinate) {
        let key = Key(frame: frame, tile: tile)
        contents.withLock {
            $0.images[key] = data
            $0.empty.remove(key)
        }
    }

    public func markEmpty(frame: String, tile: TileCoordinate) {
        let key = Key(frame: frame, tile: tile)
        contents.withLock {
            $0.images[key] = nil
            $0.empty.insert(key)
        }
    }

    /// Drops every frame not in `frames`.
    public func keep(frames: Set<String>) {
        contents.withLock {
            $0.images = $0.images.filter { frames.contains($0.key.frame) }
            $0.empty = $0.empty.filter { frames.contains($0.frame) }
        }
    }

    /// Drops every frame not in `frames` and every tile not in `tiles`.
    public func keep(frames: Set<String>, tiles: Set<TileCoordinate>) {
        contents.withLock {
            $0.images = $0.images.filter { frames.contains($0.key.frame) && tiles.contains($0.key.tile) }
            $0.empty = $0.empty.filter { frames.contains($0.frame) && tiles.contains($0.tile) }
        }
    }

    /// Image bytes held across every frame.
    public var byteCount: Int {
        contents.withLock { $0.images.values.reduce(0) { $0 + $1.count } }
    }
}
