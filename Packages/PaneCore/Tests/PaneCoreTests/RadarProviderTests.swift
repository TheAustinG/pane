import Foundation
import Testing
@testable import PaneCore

@Suite("Radar providers")
struct RadarProviderTests {
    private let tile = TileCoordinate(z: 9, x: 131, y: 190)

    @Test func iemFramesAreTheValidTimeAndElevenBeforeIt() {
        let frames = IEMRadarProvider.frames(endingAt: RadarFixture.iemValid)
        #expect(frames.count == 12)
        #expect(frames.last == RadarFrame(id: "ridge::USCOMP-N0Q-202611030100", time: RadarFixture.iemValid))
        #expect(frames.first == RadarFrame(id: "ridge::USCOMP-N0Q-202611030005", time: RadarFixture.iemValid.addingTimeInterval(-55 * 60)))
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $1.time.timeIntervalSince($0.time) == 300 })
        #expect(Set(frames.map(\.id)).count == 12)
    }

    @Test func iemFramesFloorToTheFiveMinuteMarkAndCrossMidnightInUTC() {
        let late = IEMRadarProvider.frames(endingAt: RadarFixture.iemValid.addingTimeInterval(150))
        #expect(late.last?.id == "ridge::USCOMP-N0Q-202611030100")
        let pastMidnight = IEMRadarProvider.frames(endingAt: RadarFixture.iemValid.addingTimeInterval(-40 * 60))
        #expect(pastMidnight.last?.id == "ridge::USCOMP-N0Q-202611030020")
        #expect(pastMidnight.first?.id == "ridge::USCOMP-N0Q-202611022325")
    }

    @Test func iemIndexValidTime() throws {
        #expect(try IEMRadarProvider.validTime(fromIndex: RadarFixture.iemIndex(valid: "2026-11-03T01:00:00Z")) == RadarFixture.iemValid)
        #expect(throws: RadarProviderError.badIndex) { try IEMRadarProvider.validTime(fromIndex: Data("not json".utf8)) }
        #expect(throws: RadarProviderError.badIndex) { try IEMRadarProvider.validTime(fromIndex: Data(#"{"meta": {"vcp": null}}"#.utf8)) }
        #expect(throws: RadarProviderError.badIndex) { try IEMRadarProvider.validTime(fromIndex: RadarFixture.iemIndex(valid: "yesterday")) }
    }

    @Test func iemFramesFromTheIndexRequest() async throws {
        let provider = IEMRadarProvider()
        let frames = try await provider.frames { url in
            #expect(url == IEMRadarProvider.indexURL)
            return RadarResponse(status: 200, data: RadarFixture.iemIndex(valid: "2026-11-03T01:00:00Z"))
        }
        #expect(frames == IEMRadarProvider.frames(endingAt: RadarFixture.iemValid))
        await #expect(throws: RadarProviderError.badStatus(503)) {
            try await provider.frames { _ in RadarResponse(status: 503, data: Data()) }
        }
    }

    @Test func iemTileURL() {
        let frame = RadarFrame(id: "ridge::USCOMP-N0Q-202611030100", time: RadarFixture.iemValid)
        #expect(
            IEMRadarProvider().tileURL(frame: frame, tile: tile)?.absoluteString
                == "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/ridge::USCOMP-N0Q-202611030100/9/131/190.png"
        )
        #expect(IEMRadarProvider().credit == "Iowa Environmental Mesonet")
    }

    @Test func iemCoversTheContinentalUSComposite() {
        let provider = IEMRadarProvider()
        let inside = [
            RadarFixture.chicago,
            GeoPoint(latitude: 25.76, longitude: -80.19),
            GeoPoint(latitude: 24.55, longitude: -81.80),
            GeoPoint(latitude: 47.61, longitude: -122.33),
            GeoPoint(latitude: 32.72, longitude: -117.16),
            GeoPoint(latitude: 44.80, longitude: -68.77),
            GeoPoint(latitude: 25.90, longitude: -97.50),
        ]
        let outside = [
            RadarFixture.london,
            GeoPoint(latitude: 61.22, longitude: -149.90),
            GeoPoint(latitude: 21.31, longitude: -157.86),
            GeoPoint(latitude: 18.47, longitude: -66.11),
            GeoPoint(latitude: 19.43, longitude: -99.13),
            GeoPoint(latitude: 53.55, longitude: -113.49),
        ]
        #expect(inside.allSatisfy(provider.covers))
        #expect(!outside.contains(where: provider.covers))
        #expect(RainViewerRadarProvider().covers(RadarFixture.london))
    }

    @Test func rainViewerIndexKeepsTheNewestTwelveOldestFirst() throws {
        let frames = try RainViewerRadarProvider.frames(fromIndex: RadarFixture.rainViewerIndex())
        #expect(frames.count == 12)
        #expect(frames.first?.time == Date(timeIntervalSince1970: 1_793_661_000))
        #expect(frames.last?.time == RadarFixture.iemValid)
        #expect(frames.last?.id == "https://tilecache.rainviewer.com/v2/radar/\(String(1_793_667_600, radix: 16))")
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $1.time.timeIntervalSince($0.time) == 600 })
    }

    @Test func rainViewerIndexSortsAndToleratesShortLists() throws {
        let shuffled = [1_793_667_000, 1_793_666_400, 1_793_667_600]
        let frames = try RainViewerRadarProvider.frames(fromIndex: RadarFixture.rainViewerIndex(times: shuffled))
        #expect(frames.map(\.time.timeIntervalSince1970) == [1_793_666_400, 1_793_667_000, 1_793_667_600])
    }

    @Test func rainViewerIndexRejectsBadShapes() {
        #expect(throws: RadarProviderError.badIndex) { try RainViewerRadarProvider.frames(fromIndex: Data("{}".utf8)) }
        #expect(throws: RadarProviderError.badIndex) { try RainViewerRadarProvider.frames(fromIndex: RadarFixture.rainViewerIndex(times: [])) }
        #expect(throws: RadarProviderError.badIndex) {
            try RainViewerRadarProvider.frames(fromIndex: RadarFixture.rainViewerIndex(host: "http://tilecache.rainviewer.com"))
        }
    }

    @Test func rainViewerTileURL() throws {
        let frame = try #require(try RainViewerRadarProvider.frames(fromIndex: RadarFixture.rainViewerIndex()).last)
        let url = RainViewerRadarProvider().tileURL(frame: frame, tile: TileCoordinate(z: 7, x: 32, y: 47))
        #expect(url?.absoluteString == "https://tilecache.rainviewer.com/v2/radar/\(String(1_793_667_600, radix: 16))/256/7/32/47/2/1_0.png")
        #expect(RainViewerRadarProvider().credit == "RainViewer")
        #expect(RainViewerRadarProvider().zoomRange.upperBound == 7)
    }

    @Test func tileOutcomes() {
        let png = RadarFixture.png + Data([1, 2, 3])
        #expect(RadarController.outcome(of: RadarResponse(status: 200, data: png)) == .stored(png))
        #expect(RadarController.outcome(of: RadarResponse(status: 200, data: Data())) == .empty)
        #expect(RadarController.outcome(of: RadarResponse(status: 204, data: Data())) == .empty)
        #expect(RadarController.outcome(of: RadarResponse(status: 404, data: Data("Not Found".utf8))) == .empty)
        #expect(RadarController.outcome(of: RadarResponse(status: 503, data: Data())) == .failed)
        #expect(RadarController.outcome(of: RadarResponse(status: 429, data: Data())) == .failed)
        #expect(RadarController.outcome(of: RadarResponse(status: 200, data: Data("<html>".utf8))) == .failed)
    }

    @Test func pacerHoldsAnyRollingMinuteToTheLimit() {
        var pacer = RequestPacer(perMinute: 90)
        let now = RadarFixture.start
        let starts = (0..<200).map { _ in pacer.reserve(at: now) }
        #expect(starts.prefix(90).allSatisfy { $0 == now })
        #expect(starts.dropFirst(90).prefix(90).allSatisfy { $0 == now.addingTimeInterval(60) })
        #expect(starts.suffix(20).allSatisfy { $0 == now.addingTimeInterval(120) })
        #expect(RadarFixture.busiestMinute(starts) == 90)
    }

    @Test func pacerDoesNotDelayRequestsUnderTheLimit() {
        var pacer = RequestPacer(perMinute: 90)
        let now = RadarFixture.start
        let starts = (0..<300).map { pacer.reserve(at: now.addingTimeInterval(Double($0))) }
        #expect(starts == (0..<300).map { now.addingTimeInterval(Double($0)) })
    }

    @Test func pacerForgetsReservationsWhenTheClockGoesBack() {
        var pacer = RequestPacer(perMinute: 2)
        let now = RadarFixture.start
        _ = (0..<6).map { _ in pacer.reserve(at: now) }
        let earlier = now.addingTimeInterval(-3600)
        #expect(pacer.reserve(at: earlier) == earlier)
    }
}
