import Foundation
import Testing
@testable import PaneCore

@Suite("Radar tile math")
struct RadarTileMathTests {
    private let viewport = RadarViewport(center: RadarFixture.chicago)

    @Test func chicagoTiles() {
        #expect(TileMath.tile(containing: RadarFixture.chicago, z: 7) == TileCoordinate(z: 7, x: 32, y: 47))
        #expect(TileMath.tile(containing: RadarFixture.chicago, z: 9) == TileCoordinate(z: 9, x: 131, y: 190))
        #expect(TileMath.tile(containing: RadarFixture.chicago, z: 0) == TileCoordinate(z: 0, x: 0, y: 0))
    }

    @Test func mercatorRoundTrips() {
        for latitude in [-80.0, -41.88, 0, 23, 41.88, 50, 80] {
            #expect(abs(TileMath.latitude(mercatorY: TileMath.mercatorY(latitude: latitude)) - latitude) < 1e-9)
        }
        #expect(TileMath.mercatorX(longitude: -180) == 0)
        #expect(TileMath.longitude(mercatorX: 0.5) == 0)
        #expect(abs(TileMath.mercatorY(latitude: 0) - 0.5) < 1e-12)
    }

    @Test func defaultViewportIs420KilometersAtTheScreensAspect() {
        let bounds = viewport.bounds
        let widthDegrees = bounds.east - bounds.west
        #expect(abs(widthDegrees * 111.32 * cos(41.88 * .pi / 180) - 420) < 1e-9)
        #expect(abs((bounds.east + bounds.west) / 2 - RadarFixture.chicago.longitude) < 1e-9)
        let mercatorHeight = TileMath.mercatorY(latitude: bounds.south) - TileMath.mercatorY(latitude: bounds.north)
        let mercatorWidth = widthDegrees / 360
        #expect(abs(mercatorHeight / mercatorWidth - 1080.0 / 1920.0) < 1e-9)
        #expect(bounds.contains(RadarFixture.chicago))
        #expect(bounds.north > 42.9 && bounds.north < 43)
        #expect(bounds.south > 40.8 && bounds.south < 40.9)
    }

    /// The zoom whose tiles draw closest to 1:1: the default viewport is z9.06 ideally.
    @Test func zoomIsNearestOneToOneWithinTheProvidersRange() {
        #expect(TileMath.zoom(for: viewport, in: IEMRadarProvider().zoomRange) == 9)
        #expect(TileMath.zoom(for: viewport, in: RainViewerRadarProvider().zoomRange) == 7)
        #expect(TileMath.zoom(for: RadarViewport(center: RadarFixture.chicago, widthKm: 4000), in: 6...10) == 6)
        #expect(TileMath.zoom(for: RadarViewport(center: RadarFixture.chicago, widthKm: 20), in: 6...10) == 10)
        #expect(TileMath.zoom(for: RadarViewport(center: RadarFixture.chicago, widthKm: 3000), in: 0...12) == 6)
    }

    @Test func tilesCoverTheBoundsRowByRow() {
        let bounds = viewport.bounds
        let tiles = TileMath.tiles(covering: bounds, z: 9)
        #expect(tiles.count == 40)
        #expect(tiles.first == TileCoordinate(z: 9, x: 127, y: 188))
        #expect(tiles.last == TileCoordinate(z: 9, x: 134, y: 192))
        #expect(Set(tiles.map(\.x)) == Set(127...134))
        #expect(Set(tiles.map(\.y)) == Set(188...192))
        #expect(tiles.map(\.y) == tiles.map(\.y).sorted())
        let corners = [
            GeoPoint(latitude: bounds.north, longitude: bounds.west),
            GeoPoint(latitude: bounds.north, longitude: bounds.east),
            GeoPoint(latitude: bounds.south, longitude: bounds.west),
            GeoPoint(latitude: bounds.south, longitude: bounds.east),
            RadarFixture.chicago,
        ]
        for corner in corners {
            #expect(tiles.contains(TileMath.tile(containing: corner, z: 9)))
        }
    }

    @Test func tilesClampAtTheEdgeOfTheWorld() {
        let world = GeoBounds(north: 89, south: -89, east: 200, west: -200)
        #expect(TileMath.tiles(covering: world, z: 1).count == 4)
        #expect(TileMath.tiles(covering: world, z: 0) == [TileCoordinate(z: 0, x: 0, y: 0)])
    }

    /// Tiles per frame times 12 frames is one full loop. IEM: 8 by 5 tiles at z9 is 480 tile
    /// requests, within two minutes of its 300 a minute cap, with the newest frame first. RainViewer
    /// at z7: 3 by 2 tiles is 72 tiles plus the index, under its 90 a minute, so no wait at all.
    @Test func requestBudgetPerLoopAtTheDefaultViewport() {
        let iem = IEMRadarProvider()
        let iemTiles = TileMath.tiles(covering: viewport.bounds, z: TileMath.zoom(for: viewport, in: iem.zoomRange))
        #expect(iemTiles.count * IEMRadarProvider.frameCount == 480)
        #expect(iemTiles.count <= iem.requestLimit.perMinute)

        let rainViewer = RainViewerRadarProvider()
        let rainViewerTiles = TileMath.tiles(covering: viewport.bounds, z: TileMath.zoom(for: viewport, in: rainViewer.zoomRange))
        #expect(rainViewerTiles.count == 6)
        #expect(rainViewerTiles.count * RainViewerRadarProvider.frameCount + 1 == 73)
        #expect(73 <= rainViewer.requestLimit.perMinute)
        #expect(rainViewer.requestLimit.perMinute < 100)
    }

    @Test func boundsContainment() {
        let box = GeoBounds(north: 50, south: 23, east: -65, west: -126)
        #expect(box.contains(GeoPoint(latitude: 50, longitude: -126)))
        #expect(!box.contains(GeoPoint(latitude: 50.01, longitude: -100)))
        #expect(!box.contains(GeoPoint(latitude: 40, longitude: -64.99)))
    }
}
