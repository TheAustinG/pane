import MapKit
import PaneCore
import SwiftUI

final class RadarMKMapView: MKMapView {
    var visibleBounds: GeoBounds? {
        didSet {
            guard visibleBounds != oldValue else { return }
            applied = nil
            setNeedsLayout()
        }
    }
    private var applied: CGSize?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let visibleBounds, bounds.width > 0, applied != bounds.size else { return }
        applied = bounds.size
        setVisibleMapRect(visibleBounds.mapRect, edgePadding: .zero, animated: false)
    }
}

/// The base map with the radar overlay. It shows exactly `bounds`, which is also the area the
/// tiles were chosen for.
struct RadarMapView: UIViewRepresentable {
    let bounds: GeoBounds
    let tiles: [TileCoordinate]
    let revision: Int
    let store: RadarTileStore
    let frame: String?
    let nextFrame: String?

    final class Coordinator: NSObject, MKMapViewDelegate {
        let images: RadarImageCache
        var overlay: RadarOverlay?
        var renderer: RadarOverlayRenderer?
        var tiles: [TileCoordinate] = []
        var latest: (frame: String?, next: String?, revision: Int) = (nil, nil, 0)

        init(store: RadarTileStore) {
            images = RadarImageCache(store: store)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let overlay = overlay as? RadarOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = RadarOverlayRenderer(overlay: overlay, images: images)
            renderer.update(frame: latest.frame, next: latest.next, tiles: tiles, revision: latest.revision)
            self.renderer = renderer
            return renderer
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> RadarMKMapView {
        let map = RadarMKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        map.pointOfInterestFilter = .excludingAll
        map.isUserInteractionEnabled = false
        return map
    }

    func updateUIView(_ map: RadarMKMapView, context: Context) {
        let coordinator = context.coordinator
        map.visibleBounds = bounds
        coordinator.latest = (frame, nextFrame, revision)
        if coordinator.overlay == nil || coordinator.tiles != tiles {
            if let old = coordinator.overlay { map.removeOverlay(old) }
            coordinator.renderer = nil
            coordinator.tiles = tiles
            let overlay = RadarOverlay(tiles: tiles, fallback: bounds.mapRect)
            coordinator.overlay = overlay
            map.addOverlay(overlay, level: .aboveRoads)
        }
        coordinator.renderer?.update(frame: frame, next: nextFrame, tiles: tiles, revision: revision)
    }
}
