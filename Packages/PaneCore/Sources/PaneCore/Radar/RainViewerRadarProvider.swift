import Foundation

/// Worldwide radar from RainViewer's free tier, the fallback outside the US or when IEM fails.
/// Personal use only, at most 100 requests per IP in any minute, and no tiles past z7.
public struct RainViewerRadarProvider: RadarTileProvider {
    public static let indexURL = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
    public static let frameCount = 12

    public var zoomRange: ClosedRange<Int>
    public var requestLimit: RadarRequestLimit

    /// 90 a minute leaves room under the free tier's 100 for retries and clock skew.
    public init(zoomRange: ClosedRange<Int> = 0...7, requestLimit: RadarRequestLimit = RadarRequestLimit(concurrent: 6, perMinute: 90)) {
        self.zoomRange = zoomRange
        self.requestLimit = requestLimit
    }

    public var credit: String { "RainViewer" }

    /// New frames arrive every 10 minutes.
    public var refreshInterval: TimeInterval { 10 * 60 }

    public func covers(_ point: GeoPoint) -> Bool { true }

    public func frames(using fetch: RadarFetch) async throws -> [RadarFrame] {
        let response = try await fetch(Self.indexURL)
        guard response.status == 200 else { throw RadarProviderError.badStatus(response.status) }
        return try Self.frames(fromIndex: response.data)
    }

    /// Frame ids are the index's host and path, the prefix of every tile URL in the frame.
    public func tileURL(frame: RadarFrame, tile: TileCoordinate) -> URL? {
        URL(string: "\(frame.id)/256/\(tile.z)/\(tile.x)/\(tile.y)/2/1_0.png")
    }

    /// The newest `count` past frames of the index, oldest first.
    public static func frames(fromIndex data: Data, count: Int = frameCount) throws -> [RadarFrame] {
        struct Index: Decodable {
            struct Radar: Decodable { let past: [Entry] }
            struct Entry: Decodable {
                let time: TimeInterval
                let path: String
            }
            let host: String
            let radar: Radar
        }
        guard let index = try? JSONDecoder().decode(Index.self, from: data), index.host.hasPrefix("https://") else {
            throw RadarProviderError.badIndex
        }
        let entries = index.radar.past.filter { $0.path.hasPrefix("/") }.sorted { $0.time < $1.time }
        guard !entries.isEmpty else { throw RadarProviderError.badIndex }
        return entries.suffix(count).map { entry in
            RadarFrame(id: index.host + entry.path, time: Date(timeIntervalSince1970: entry.time))
        }
    }
}
