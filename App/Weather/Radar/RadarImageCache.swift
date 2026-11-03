import PaneCore
import Synchronization
import UIKit

/// Decoded radar tiles for the whole loop, so frames decode once rather than on every pass.
/// Fully transparent tiles, most of a clear-sky frame, are remembered and never kept as images.
final class RadarImageCache: @unchecked Sendable {
    private let store: RadarTileStore
    private let cache = NSCache<NSString, UIImage>()
    private let blank = Mutex<Set<String>>([])

    /// Twelve frames of about 40 tiles at 256 KB each, if every tile had echoes.
    private static let byteLimit = 128 << 20
    private static let blankLimit = 5000

    init(store: RadarTileStore) {
        self.store = store
        cache.totalCostLimit = Self.byteLimit
    }

    func image(frame: String, tile: TileCoordinate) -> UIImage? {
        let key = "\(frame)/\(tile.z)/\(tile.x)/\(tile.y)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if blank.withLock({ $0.contains(key) }) { return nil }
        guard let data = store.data(frame: frame, tile: tile),
              let image = UIImage(data: data) else { return nil }
        let decoded = image.preparingForDisplay() ?? image
        guard let cgImage = decoded.cgImage, !Self.isTransparent(cgImage) else {
            blank.withLock { keys in
                if keys.count >= Self.blankLimit { keys.removeAll() }
                keys.insert(key)
            }
            return nil
        }
        cache.setObject(decoded, forKey: key as NSString, cost: cgImage.bytesPerRow * cgImage.height)
        return decoded
    }

    func prefetch(frame: String, tiles: [TileCoordinate]) {
        Task.detached(priority: .utility) { [self] in
            for tile in tiles { _ = image(frame: frame, tile: tile) }
        }
    }

    func isComplete(frame: String, tiles: [TileCoordinate]) -> Bool {
        tiles.allSatisfy { store.isResolved(frame: frame, tile: $0) }
    }

    private static func isTransparent(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn && !alpha.contains { $0 != 0 }
    }
}
