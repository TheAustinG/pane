import Foundation

/// NEXRAD base reflectivity over the continental US from the Iowa Environmental Mesonet. Each frame
/// is an absolute timestamped layer, so its tiles never change and a refresh fetches only the new frame.
public struct IEMRadarProvider: RadarTileProvider {
    public static let indexURL = URL(string: "https://mesonet.agron.iastate.edu/data/gis/images/4326/USCOMP/n0q_0.json")!
    public static let tileBase = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/"
    /// The USCOMP composite grid: 0.005 degree cells from 126W to 65W and 23N to 50N.
    public static let coverage = GeoBounds(north: 50, south: 23, east: -65, west: -126)
    public static let frameCount = 12
    public static let frameStep: TimeInterval = 5 * 60

    public var zoomRange: ClosedRange<Int>
    public var requestLimit: RadarRequestLimit

    /// z9 draws the default 420 km viewport near 1:1; z5 to z12 were checked to serve tiles.
    public init(zoomRange: ClosedRange<Int> = 6...10, requestLimit: RadarRequestLimit = RadarRequestLimit(concurrent: 6, perMinute: 300)) {
        self.zoomRange = zoomRange
        self.requestLimit = requestLimit
    }

    public var credit: String { "Iowa Environmental Mesonet" }

    /// The composite updates every 5 minutes.
    public var refreshInterval: TimeInterval { Self.frameStep }

    public func covers(_ point: GeoPoint) -> Bool {
        Self.coverage.contains(point)
    }

    public func frames(using fetch: RadarFetch) async throws -> [RadarFrame] {
        let response = try await fetch(Self.indexURL)
        guard response.status == 200 else { throw RadarProviderError.badStatus(response.status) }
        return Self.frames(endingAt: try Self.validTime(fromIndex: response.data))
    }

    public func tileURL(frame: RadarFrame, tile: TileCoordinate) -> URL? {
        URL(string: "\(Self.tileBase)\(frame.id)/\(tile.z)/\(tile.x)/\(tile.y).png")
    }

    /// `meta.valid` of the index, the newest composite time.
    public static func validTime(fromIndex data: Data) throws -> Date {
        struct Index: Decodable {
            struct Meta: Decodable { let valid: String }
            let meta: Meta
        }
        guard let index = try? JSONDecoder().decode(Index.self, from: data),
              let valid = try? Date.ISO8601FormatStyle().parse(index.meta.valid) else {
            throw RadarProviderError.badIndex
        }
        return valid
    }

    /// `valid` and the frames before it at 5-minute steps, oldest first. Layers exist only on the
    /// 5-minute marks, so `valid` is floored to one.
    public static func frames(endingAt valid: Date) -> [RadarFrame] {
        let newest = (valid.timeIntervalSince1970 / frameStep).rounded(.down) * frameStep
        return (0..<frameCount).reversed().map { back in
            let time = Date(timeIntervalSince1970: newest - Double(back) * frameStep)
            return RadarFrame(id: layer(at: time), time: time)
        }
    }

    /// For example `ridge::USCOMP-N0Q-202611030100` for 01:00 UTC on 3 November 2026.
    public static func layer(at time: Date) -> String {
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: time)
        let stamp = [(parts.year, 4), (parts.month, 2), (parts.day, 2), (parts.hour, 2), (parts.minute, 2)]
            .map { value, width in
                let digits = String(value ?? 0)
                return String(repeating: "0", count: max(width - digits.count, 0)) + digits
            }
            .joined()
        return "ridge::USCOMP-N0Q-\(stamp)"
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
