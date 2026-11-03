import MapKit
import PaneCore
import Synchronization

extension TileCoordinate {
    var mapRect: MKMapRect {
        let size = MKMapSize.world.width / Double(1 << z)
        return MKMapRect(x: Double(x) * size, y: Double(y) * size, width: size, height: size)
    }
}

extension GeoBounds {
    var mapRect: MKMapRect {
        let northWest = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let southEast = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        return MKMapRect(x: northWest.x, y: northWest.y, width: southEast.x - northWest.x, height: southEast.y - northWest.y)
    }
}

/// One overlay for the whole radar loop: the renderer swaps which frame it draws.
final class RadarOverlay: NSObject, MKOverlay {
    let boundingMapRect: MKMapRect
    var coordinate: CLLocationCoordinate2D { boundingMapRect.origin.coordinate }

    init(tiles: [TileCoordinate], fallback: MKMapRect) {
        let covered = tiles.map(\.mapRect).reduce(MKMapRect.null) { $0.union($1) }
        boundingMapRect = covered.isNull ? fallback : covered
    }
}

/// Draws the shown frame's tiles. `MKTileOverlayRenderer` never draws on tvOS, and an overlay per
/// frame redraws every frame on each flip.
final class RadarOverlayRenderer: MKOverlayRenderer {
    private struct Shown {
        var frame: String?
        var next: String?
        var tiles: [TileCoordinate] = []
        var revision = 0
    }

    private let images: RadarImageCache
    private let shown = Mutex(Shown())

    init(overlay: RadarOverlay, images: RadarImageCache) {
        self.images = images
        super.init(overlay: overlay)
        alpha = 0.8
    }

    /// Call on the main thread.
    func update(frame: String?, next: String?, tiles: [TileCoordinate], revision: Int) {
        let previous = shown.withLock { state -> Shown in
            let old = state
            state = Shown(frame: frame, next: next, tiles: tiles, revision: revision)
            return old
        }
        if let next, next != frame, next != previous.next || tiles != previous.tiles {
            images.prefetch(frame: next, tiles: tiles)
        }
        let frameChanged = frame != previous.frame || tiles != previous.tiles
        let tilesArrived = revision != previous.revision && frame.map { !images.isComplete(frame: $0, tiles: tiles) } == true
        if frameChanged || tilesArrived { setNeedsDisplay() }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let (frame, tiles) = shown.withLock { ($0.frame, $0.tiles) }
        guard let frame else { return }
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        for tile in tiles {
            let tileRect = tile.mapRect
            guard tileRect.intersects(mapRect), let image = images.image(frame: frame, tile: tile) else { continue }
            image.draw(in: rect(for: tileRect))
        }
    }
}
