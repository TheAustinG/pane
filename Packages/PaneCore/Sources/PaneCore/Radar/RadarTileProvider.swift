import Foundation

/// A source of radar frames and tiles. `RadarController` prefers the first provider in its list
/// that covers the viewport center and falls back to the next when it fails.
public protocol RadarTileProvider: Sendable {
    /// Who to credit on screen.
    var credit: String { get }
    var zoomRange: ClosedRange<Int> { get }
    /// How often the frame index is read again while radar runs.
    var refreshInterval: TimeInterval { get }
    var requestLimit: RadarRequestLimit { get }
    func covers(_ point: GeoPoint) -> Bool
    /// The frames to loop, oldest first, from a single index request.
    func frames(using fetch: RadarFetch) async throws -> [RadarFrame]
    func tileURL(frame: RadarFrame, tile: TileCoordinate) -> URL?
}

/// How hard one provider may be asked: requests in flight at once, and requests in any rolling minute.
public struct RadarRequestLimit: Hashable, Sendable {
    public var concurrent: Int
    public var perMinute: Int

    public init(concurrent: Int, perMinute: Int) {
        self.concurrent = concurrent
        self.perMinute = perMinute
    }
}

public struct RadarResponse: Hashable, Sendable {
    public var status: Int
    public var data: Data

    public init(status: Int, data: Data) {
        self.status = status
        self.data = data
    }
}

/// Fetches a URL; injected so tests never touch the network.
public typealias RadarFetch = @Sendable (URL) async throws -> RadarResponse

public enum RadarProviderError: Error, Hashable, Sendable {
    case badStatus(Int)
    case badIndex
    /// The newest frame is too old to show, as when a composite stops updating.
    case staleIndex
}

public enum RadarNetwork {
    /// No URL cache: tiles live in `RadarTileStore`, and a cached index would hide new frames.
    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    public static func fetch(_ url: URL) async throws -> RadarResponse {
        let (data, response) = try await session.data(from: url)
        return RadarResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }
}

/// Spaces requests so that no rolling minute holds more than `perMinute` of them.
struct RequestPacer: Hashable, Sendable {
    let perMinute: Int
    /// Start times of the latest reservations, oldest first; only the last `perMinute` matter.
    private(set) var starts: [Date] = []

    init(perMinute: Int) {
        self.perMinute = max(perMinute, 1)
    }

    /// Reserves the earliest start at or after `now` that keeps the limit, and returns it.
    mutating func reserve(at now: Date) -> Date {
        // Reservations never lead `now` by much more than a minute, so a bigger lead means the clock went back.
        if let last = starts.last, last.timeIntervalSince(now) > 120 {
            starts.removeAll()
        }
        var start = max(now, starts.last ?? now)
        if starts.count >= perMinute {
            start = max(start, starts[starts.count - perMinute].addingTimeInterval(60))
        }
        starts.append(start)
        if starts.count > perMinute {
            starts.removeFirst(starts.count - perMinute)
        }
        return start
    }
}
