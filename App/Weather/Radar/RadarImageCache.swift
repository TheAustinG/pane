import PaneCore
import UIKit

/// Decoded radar tiles. A decoded tile is about 256 KB, so only the frames near the one on screen
/// are kept.
final class RadarImageCache: @unchecked Sendable {
    private let store: RadarTileStore
    private let cache = NSCache<NSString, UIImage>()

    init(store: RadarTileStore) {
        self.store = store
    }

    func keep(tileCount: Int) {
        cache.countLimit = max(tileCount, 1) * 3
    }

    func image(frame: String, tile: TileCoordinate) -> UIImage? {
        let key = "\(frame)/\(tile.z)/\(tile.x)/\(tile.y)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = store.data(frame: frame, tile: tile),
              let image = UIImage(data: data) else { return nil }
        let decoded = image.preparingForDisplay() ?? image
        cache.setObject(decoded, forKey: key)
        return decoded
    }

    func prefetch(frame: String, tiles: [TileCoordinate]) {
        Task.detached(priority: .utility) { [self] in
            for tile in tiles { _ = image(frame: frame, tile: tile) }
        }
    }

    func isComplete(frame: String, tiles: [TileCoordinate]) -> Bool {
        tiles.allSatisfy { store.contains(frame: frame, tile: $0) }
    }
}
