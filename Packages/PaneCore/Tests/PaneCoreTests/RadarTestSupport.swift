import Foundation
import Synchronization
@testable import PaneCore

/// Hand-written index bodies shaped like the live IEM and RainViewer responses.
enum RadarFixture {
    static let chicago = WeatherFixture.chicago
    static let london = GeoPoint(latitude: 51.5, longitude: -0.12)
    /// 2026-11-03T01:00:00Z.
    static let iemValid = Date(timeIntervalSince1970: 1_793_667_600)
    /// 2026-11-03T01:07:00Z.
    static let start = iemValid.addingTimeInterval(7 * 60)
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    static func iemIndex(valid: String) -> Data {
        Data("""
        {"meta": {"vcp": null, "product": "N0Q", "site": "USCOMP", "valid": "\(valid)", "processing_time_secs": 112, "radar_quorum": "144/147"}}
        """.utf8)
    }

    /// 13 past frames 600 s apart, the newest at 2026-11-03T01:00:00Z.
    static let rainViewerTimes = (0..<13).map { 1_793_660_400 + $0 * 600 }

    static func rainViewerPath(_ time: Int) -> String {
        "/v2/radar/\(String(time, radix: 16))"
    }

    static func rainViewerIndex(times: [Int] = rainViewerTimes, host: String = "https://tilecache.rainviewer.com") -> Data {
        let past = times.map { #"{"time":\#($0),"path":"\#(rainViewerPath($0))"}"# }.joined(separator: ",")
        return Data("""
        {"version":"2.0","generated":1793667632,"host":"\(host)","radar":{"past":[\(past)],"nowcast":[]},"satellite":{"infrared":[]}}
        """.utf8)
    }

    /// The largest number of `times` that fall in any 60-second window.
    static func busiestMinute(_ times: [Date]) -> Int {
        let sorted = times.sorted()
        var busiest = 0
        var low = 0
        for high in sorted.indices {
            while sorted[high].timeIntervalSince(sorted[low]) >= 60 { low += 1 }
            busiest = max(busiest, high - low + 1)
        }
        return busiest
    }
}

/// Answers radar requests from settable fixtures and records each one with the clock time.
final class RadarNetworkStub: Sendable {
    struct Request: Hashable, Sendable {
        let url: URL
        let time: Date
    }

    private struct State {
        var iemValid: String? = "2026-11-03T01:00:00Z"
        var rainViewerTimes: [Int]? = RadarFixture.rainViewerTimes
        var tileStatus: @Sendable (URL) -> Int = { _ in 200 }
        var requests: [Request] = []
    }

    private let state = Mutex(State())
    private let clock: ManualClock

    init(clock: ManualClock) {
        self.clock = clock
    }

    var fetch: RadarFetch {
        { [self] url in try respond(to: url) }
    }

    var requests: [Request] { state.withLock { $0.requests } }
    var urls: [String] { requests.map(\.url.absoluteString) }
    var tileURLs: [String] { urls.filter { !$0.hasSuffix(".json") } }

    /// Nil makes the index fail.
    func setIEMValid(_ valid: String?) {
        state.withLock { $0.iemValid = valid }
    }

    /// Nil makes the index fail.
    func setRainViewerTimes(_ times: [Int]?) {
        state.withLock { $0.rainViewerTimes = times }
    }

    func setTileStatus(_ status: @escaping @Sendable (URL) -> Int) {
        state.withLock { $0.tileStatus = status }
    }

    func clearRequests() {
        state.withLock { $0.requests = [] }
    }

    private func respond(to url: URL) throws -> RadarResponse {
        let now = clock.now
        let (iemValid, rainViewerTimes, tileStatus) = state.withLock { state in
            state.requests.append(Request(url: url, time: now))
            return (state.iemValid, state.rainViewerTimes, state.tileStatus)
        }
        switch url {
        case IEMRadarProvider.indexURL:
            guard let iemValid else { throw URLError(.cannotConnectToHost) }
            return RadarResponse(status: 200, data: RadarFixture.iemIndex(valid: iemValid))
        case RainViewerRadarProvider.indexURL:
            guard let rainViewerTimes else { throw URLError(.cannotConnectToHost) }
            return RadarResponse(status: 200, data: RadarFixture.rainViewerIndex(times: rainViewerTimes))
        default:
            let status = tileStatus(url)
            return RadarResponse(status: status, data: status == 200 ? RadarFixture.png + Data(url.absoluteString.utf8) : Data())
        }
    }
}
