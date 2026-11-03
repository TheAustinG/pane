import Foundation

/// A Web Mercator (slippy map) tile.
public struct TileCoordinate: Hashable, Sendable, Codable {
    public var z: Int
    public var x: Int
    public var y: Int

    public init(z: Int, x: Int, y: Int) {
        self.z = z
        self.x = x
        self.y = y
    }
}

/// One radar image time. `id` is the provider's layer key, unique per frame.
public struct RadarFrame: Hashable, Sendable, Identifiable {
    public var id: String
    public var time: Date

    public init(id: String, time: Date) {
        self.id = id
        self.time = time
    }
}

/// Latitude and longitude edges in degrees.
public struct GeoBounds: Hashable, Sendable {
    public var north: Double
    public var south: Double
    public var east: Double
    public var west: Double

    public init(north: Double, south: Double, east: Double, west: Double) {
        self.north = north
        self.south = south
        self.east = east
        self.west = west
    }

    /// Edges count as inside. Assumes the bounds do not cross the antimeridian.
    public func contains(_ point: GeoPoint) -> Bool {
        (south...north).contains(point.latitude) && (west...east).contains(point.longitude)
    }
}

/// The map area the takeover shows, sized in screen points so the controller can pick a zoom whose
/// tiles draw near 1:1.
public struct RadarViewport: Hashable, Sendable {
    public var center: GeoPoint
    /// East to west extent at the center latitude.
    public var widthKm: Double
    public var pointsWide: Double
    public var pointsHigh: Double

    public init(center: GeoPoint, widthKm: Double = 420, pointsWide: Double = 1920, pointsHigh: Double = 1080) {
        self.center = center
        self.widthKm = widthKm
        self.pointsWide = pointsWide
        self.pointsHigh = pointsHigh
    }

    /// The visible edges in Web Mercator, so MapKit and the tiles line up.
    public var bounds: GeoBounds {
        let widthDegrees = widthKm / (111.32 * cos(center.latitude * .pi / 180))
        let halfX = widthDegrees / 360 / 2
        let halfY = halfX * pointsHigh / pointsWide
        let y = TileMath.mercatorY(latitude: center.latitude)
        return GeoBounds(
            north: TileMath.latitude(mercatorY: y - halfY),
            south: TileMath.latitude(mercatorY: y + halfY),
            east: center.longitude + widthDegrees / 2,
            west: center.longitude - widthDegrees / 2
        )
    }
}

/// Web Mercator helpers. Mercator x and y run 0 to 1 from the top left of the world.
public enum TileMath {
    public static func mercatorX(longitude: Double) -> Double {
        (longitude + 180) / 360
    }

    public static func mercatorY(latitude: Double) -> Double {
        let radians = latitude * .pi / 180
        return (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2
    }

    public static func latitude(mercatorY y: Double) -> Double {
        atan(sinh(.pi * (1 - 2 * y))) * 180 / .pi
    }

    public static func longitude(mercatorX x: Double) -> Double {
        x * 360 - 180
    }

    /// The zoom whose 256-point tiles draw closest to 1:1 across the viewport, clamped to `range`.
    public static func zoom(for viewport: RadarViewport, in range: ClosedRange<Int>) -> Int {
        let bounds = viewport.bounds
        let fraction = (bounds.east - bounds.west) / 360
        let ideal = log2(viewport.pointsWide / (fraction * 256))
        return min(max(Int(ideal.rounded()), range.lowerBound), range.upperBound)
    }

    public static func tile(containing point: GeoPoint, z: Int) -> TileCoordinate {
        let count = 1 << z
        func index(_ value: Double) -> Int { min(max(Int(floor(value * Double(count))), 0), count - 1) }
        return TileCoordinate(z: z, x: index(mercatorX(longitude: point.longitude)), y: index(mercatorY(latitude: point.latitude)))
    }

    /// Every tile at `z` that touches `bounds`, row by row from the top left.
    public static func tiles(covering bounds: GeoBounds, z: Int) -> [TileCoordinate] {
        let count = 1 << z
        func index(_ value: Double) -> Int { min(max(Int(floor(value * Double(count))), 0), count - 1) }
        let minX = index(mercatorX(longitude: bounds.west))
        let maxX = index(mercatorX(longitude: bounds.east))
        let minY = index(mercatorY(latitude: bounds.north))
        let maxY = index(mercatorY(latitude: bounds.south))
        return (minY...maxY).flatMap { y in (minX...maxX).map { x in TileCoordinate(z: z, x: x, y: y) } }
    }
}
