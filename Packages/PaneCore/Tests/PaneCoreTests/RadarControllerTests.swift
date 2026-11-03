import Foundation
import Testing
@testable import PaneCore

private let start = RadarFixture.start
private let iemIndex = IEMRadarProvider.indexURL.absoluteString
private let rainViewerIndex = RainViewerRadarProvider.indexURL.absoluteString
private let iemCredit = "Iowa Environmental Mesonet"
private let newestLayer = "ridge::USCOMP-N0Q-202611030100"

@MainActor
private struct Harness {
    let clock = ManualClock(now: start)
    let network: RadarNetworkStub
    let controller: RadarController

    init(viewport: RadarViewport? = RadarViewport(center: RadarFixture.chicago)) {
        network = RadarNetworkStub(clock: clock)
        controller = RadarController(viewport: viewport, fetch: network.fetch, clock: clock)
    }

    func launch() async -> (task: Task<Void, Never>, wake: Date) {
        let controller = controller
        let task = Task { await controller.run() }
        return (task, await settle())
    }

    /// Lets request pacing elapse until the loop sleeps until its next cycle, and returns that time.
    func settle() async -> Date {
        while true {
            let deadline = await clock.nextSleep()
            if let wake = controller.sleepingUntil, wake == deadline { return wake }
            clock.advance(by: deadline.timeIntervalSince(clock.now))
        }
    }

    func advance(by interval: TimeInterval) async -> Date {
        clock.advance(by: interval)
        return await settle()
    }

    func advance(to date: Date) async -> Date {
        await advance(by: date.timeIntervalSince(clock.now))
    }
}

private func stop(_ task: Task<Void, Never>) async {
    task.cancel()
    await task.value
}

@Suite("Radar controller", .timeLimit(.minutes(1)))
@MainActor
struct RadarControllerTests {
    @Test func coldLoadUsesIEMNewestFrameFirstWithinItsCap() async {
        let harness = Harness()
        let controller = harness.controller
        #expect(controller.phase == .idle)
        #expect(controller.zoom == 9)
        #expect(controller.tiles.count == 40)

        let (task, wake) = await harness.launch()
        let urls = harness.network.urls
        #expect(urls.count == 1 + 12 * 40)
        #expect(urls.first == iemIndex)
        #expect(urls[1...40].allSatisfy { $0.contains("/\(newestLayer)/9/") })
        #expect(urls[41...80].allSatisfy { $0.contains("/ridge::USCOMP-N0Q-202611030055/9/") })
        #expect(controller.credit == iemCredit)
        #expect(controller.frames == IEMRadarProvider.frames(endingAt: RadarFixture.iemValid))
        #expect(controller.readyFrames == controller.frames)
        #expect(controller.phase == .ready)
        #expect(controller.revision == 480)
        #expect(controller.store.data(frame: newestLayer, tile: controller.tiles[0])?.starts(with: RadarFixture.png) == true)

        let times = harness.network.requests.map(\.time)
        #expect(times.filter { $0 == start }.count == 300)
        #expect(RadarFixture.busiestMinute(times) == 300)
        #expect(times.last == start.addingTimeInterval(60))
        #expect(wake == start.addingTimeInterval(300))
        await stop(task)
    }

    @Test func refreshFetchesOnlyTheNewFrame() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, wake) = await harness.launch()
        let oldest = controller.frames[0].id

        harness.network.clearRequests()
        harness.network.setIEMValid("2026-11-03T01:05:00Z")
        let next = await harness.advance(to: wake)
        #expect(harness.network.urls.first == iemIndex)
        #expect(harness.network.tileURLs.count == 40)
        #expect(harness.network.tileURLs.allSatisfy { $0.contains("/ridge::USCOMP-N0Q-202611030105/9/") })
        #expect(controller.frames.first?.id == "ridge::USCOMP-N0Q-202611030010")
        #expect(controller.frames.last?.id == "ridge::USCOMP-N0Q-202611030105")
        #expect(controller.readyFrameIDs.count == 12)
        #expect(!controller.tiles.contains { controller.store.isResolved(frame: oldest, tile: $0) })
        #expect(next == wake.addingTimeInterval(300))

        harness.network.clearRequests()
        _ = await harness.advance(by: 300)
        #expect(harness.network.urls == [iemIndex])
        await stop(task)
    }

    @Test func emptyTilesResolveWithoutStoringAnything() async {
        let harness = Harness()
        let controller = harness.controller
        harness.network.setTileStatus { url in
            let x = Int(url.pathComponents[url.pathComponents.count - 2]) ?? 0
            return x.isMultiple(of: 2) ? 404 : 200
        }
        let (task, _) = await harness.launch()
        #expect(controller.readyFrames.count == 12)
        let empty = controller.tiles.filter { $0.x.isMultiple(of: 2) }
        #expect(!empty.isEmpty)
        #expect(empty.allSatisfy { controller.store.isResolved(frame: newestLayer, tile: $0) })
        #expect(empty.allSatisfy { controller.store.data(frame: newestLayer, tile: $0) == nil })
        #expect(controller.revision == 12 * (40 - empty.count))
        await stop(task)
    }

    @Test func failedTilesAreRetriedAfterAMinute() async {
        let harness = Harness()
        let controller = harness.controller
        let stuck = "/\(newestLayer)/9/131/190.png"
        harness.network.setTileStatus { url in url.absoluteString.hasSuffix(stuck) ? 503 : 200 }
        let (task, wake) = await harness.launch()
        #expect(controller.readyFrameIDs.count == 11)
        #expect(!controller.readyFrameIDs.contains(newestLayer))
        #expect(controller.phase == .ready)
        #expect(controller.credit == iemCredit)
        #expect(wake == harness.clock.now.addingTimeInterval(60))

        harness.network.clearRequests()
        harness.network.setTileStatus { _ in 200 }
        let next = await harness.advance(to: wake)
        #expect(harness.network.tileURLs.count == 1)
        #expect(harness.network.tileURLs.first?.hasSuffix(stuck) == true)
        #expect(controller.readyFrameIDs.count == 12)
        #expect(next == start.addingTimeInterval(300))
        await stop(task)
    }

    @Test func rainViewerOutsideIEMCoverageStaysUnder90RequestsAMinute() async {
        let harness = Harness(viewport: RadarViewport(center: RadarFixture.london))
        let controller = harness.controller
        #expect(controller.zoom == 7)
        #expect(controller.tiles.count == 12)

        let (task, wake) = await harness.launch()
        let urls = harness.network.urls
        #expect(urls.first == rainViewerIndex)
        #expect(!urls.contains { $0.contains("mesonet") })
        #expect(urls.count == 1 + 12 * 12)
        #expect(urls[1...12].allSatisfy { $0.contains(RadarFixture.rainViewerPath(1_793_667_600)) })
        #expect(controller.credit == "RainViewer")
        #expect(controller.readyFrames.count == 12)

        let times = harness.network.requests.map(\.time)
        #expect(times.filter { $0 == start }.count == 90)
        #expect(RadarFixture.busiestMinute(times) == 90)
        #expect(wake == start.addingTimeInterval(600))
        await stop(task)
    }

    @Test func iemIndexFailureFallsBackToRainViewerAndReturnsLater() async {
        let harness = Harness()
        let controller = harness.controller
        harness.network.setIEMValid(nil)
        let (task, wake) = await harness.launch()
        let urls = harness.network.urls
        #expect(Array(urls.prefix(2)) == [iemIndex, rainViewerIndex])
        #expect(urls.count == 2 + 12 * 6)
        #expect(harness.network.requests.allSatisfy { $0.time == start })
        #expect(controller.credit == "RainViewer")
        #expect(controller.zoom == 7)
        #expect(controller.tiles.count == 6)
        #expect(controller.readyFrames.count == 12)
        #expect(wake == start.addingTimeInterval(600))

        harness.network.setIEMValid("2026-11-03T01:00:00Z")
        harness.network.clearRequests()
        let comeback = await harness.advance(to: wake)
        #expect(harness.network.urls == [rainViewerIndex])
        #expect(comeback == start.addingTimeInterval(RadarController.failoverDuration))

        harness.network.clearRequests()
        _ = await harness.advance(to: comeback)
        #expect(harness.network.urls.first == iemIndex)
        #expect(!harness.network.urls.contains { $0.contains("rainviewer") })
        #expect(controller.credit == iemCredit)
        #expect(controller.zoom == 9)
        #expect(controller.readyFrames.count == 12)
        await stop(task)
    }

    @Test func aStalledIEMCompositeFallsBackToRainViewer() async {
        let harness = Harness()
        harness.network.setIEMValid("2026-11-02T23:55:00Z")
        let (task, _) = await harness.launch()
        #expect(Array(harness.network.urls.prefix(2)) == [iemIndex, rainViewerIndex])
        #expect(harness.controller.credit == "RainViewer")
        #expect(harness.controller.readyFrames.count == 12)
        await stop(task)
    }

    @Test func anIEMCompositeUnderAnHourOldIsStillShown() async {
        let harness = Harness()
        harness.network.setIEMValid("2026-11-03T00:10:00Z")
        let (task, _) = await harness.launch()
        #expect(harness.controller.credit == iemCredit)
        #expect(harness.controller.frames.last?.id == "ridge::USCOMP-N0Q-202611030010")
        await stop(task)
    }

    @Test func mostIEMTilesFailingFallsBackAfterTheNewestFrame() async {
        let harness = Harness()
        let controller = harness.controller
        harness.network.setTileStatus { url in url.host() == "mesonet.agron.iastate.edu" ? 503 : 200 }
        let (task, _) = await harness.launch()
        let iemTiles = harness.network.tileURLs.filter { $0.contains("mesonet") }
        #expect(iemTiles.count == 40)
        #expect(iemTiles.allSatisfy { $0.contains(newestLayer) })
        #expect(harness.network.urls.contains(rainViewerIndex))
        #expect(controller.credit == "RainViewer")
        #expect(controller.readyFrames.count == 12)
        #expect(controller.phase == .ready)
        await stop(task)
    }

    @Test func iemKeepsItsFramesThroughTwoFailuresAndGivesWayAtTheThird() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, wake) = await harness.launch()
        harness.network.setIEMValid(nil)

        let first = await harness.advance(to: wake)
        #expect(controller.credit == iemCredit)
        #expect(controller.readyFrames.count == 12)
        #expect(first == wake.addingTimeInterval(60))

        let second = await harness.advance(to: first)
        #expect(controller.credit == iemCredit)
        #expect(controller.phase == .ready)

        harness.network.clearRequests()
        let third = await harness.advance(to: second)
        #expect(Array(harness.network.urls.prefix(2)) == [iemIndex, rainViewerIndex])
        #expect(controller.credit == "RainViewer")
        #expect(controller.readyFrames.count == 12)
        #expect(third == second.addingTimeInterval(600))
        await stop(task)
    }

    @Test func everyProviderFailingShowsFailedAndRetriesFromTheTop() async {
        let harness = Harness()
        let controller = harness.controller
        harness.network.setIEMValid(nil)
        harness.network.setRainViewerTimes(nil)
        let (task, wake) = await harness.launch()
        #expect(controller.phase == .failed(RadarController.failureMessage))
        #expect(harness.network.urls == [iemIndex, rainViewerIndex])
        #expect(controller.frames.isEmpty)
        #expect(wake == start.addingTimeInterval(60))

        harness.network.setIEMValid("2026-11-03T01:00:00Z")
        harness.network.clearRequests()
        _ = await harness.advance(to: wake)
        #expect(harness.network.urls.first == iemIndex)
        #expect(controller.credit == iemCredit)
        #expect(controller.phase == .ready)
        await stop(task)
    }

    @Test func framesOlderThanAnHourAreDroppedWhileEverythingFails() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, _) = await harness.launch()
        harness.network.setIEMValid(nil)
        harness.network.setRainViewerTimes(nil)

        var steps = 0
        while controller.phase != .failed(RadarController.failureMessage), steps < 120 {
            _ = await harness.advance(by: 60)
            steps += 1
        }
        #expect(harness.clock.now == RadarFixture.iemValid.addingTimeInterval(61 * 60))
        #expect(controller.frames.isEmpty)
        #expect(controller.credit == nil)
        #expect(controller.store.byteCount == 0)
        await stop(task)
    }

    @Test func viewportChangeFetchesOnlyTheMissingTiles() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, wake) = await harness.launch()

        harness.network.clearRequests()
        controller.viewport = RadarViewport(center: GeoPoint(latitude: 41.88, longitude: -87.13))
        let next = await harness.settle()
        #expect(controller.zoom == 9)
        #expect(Set(controller.tiles.map(\.x)) == Set(128...135))
        #expect(harness.network.tileURLs.count == 12 * 5)
        #expect(harness.network.tileURLs.allSatisfy { $0.contains("/9/135/") })
        #expect(!harness.network.urls.contains(iemIndex))
        #expect(controller.readyFrames.count == 12)
        #expect(!controller.store.isResolved(frame: newestLayer, tile: TileCoordinate(z: 9, x: 127, y: 190)))
        #expect(next == wake)
        await stop(task)
    }

    @Test func viewportOutsideCoverageSwitchesToRainViewer() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, _) = await harness.launch()

        harness.network.clearRequests()
        controller.viewport = RadarViewport(center: RadarFixture.london)
        #expect(controller.frames.isEmpty)
        #expect(controller.credit == nil)
        #expect(controller.zoom == 7)
        #expect(controller.phase == .loading)

        _ = await harness.settle()
        #expect(harness.network.urls.first == rainViewerIndex)
        #expect(controller.credit == "RainViewer")
        #expect(controller.readyFrames.count == 12)
        #expect(!controller.store.isResolved(frame: newestLayer, tile: TileCoordinate(z: 9, x: 131, y: 190)))
        #expect(controller.store.byteCount > 0)
        await stop(task)
    }

    @Test func loadingUntilAViewportArrives() async {
        let harness = Harness(viewport: nil)
        let controller = harness.controller
        let (task, wake) = await harness.launch()
        #expect(controller.phase == .loading)
        #expect(harness.network.urls.isEmpty)
        #expect(wake == start.addingTimeInterval(3600))

        controller.viewport = RadarViewport(center: RadarFixture.chicago)
        _ = await harness.settle()
        #expect(controller.phase == .ready)
        #expect(controller.credit == iemCredit)
        await stop(task)
    }

    @Test func aSecondRunFetchesOnlyWhatIsNew() async {
        let harness = Harness()
        let controller = harness.controller
        let (task, _) = await harness.launch()
        await stop(task)
        #expect(controller.phase == .ready)

        harness.network.clearRequests()
        let (second, wake) = await harness.launch()
        #expect(harness.network.urls.isEmpty)
        #expect(wake == start.addingTimeInterval(300))
        await stop(second)
    }

    @Test func cancellingTheTaskEndsTheLoop() async {
        let harness = Harness()
        let (task, _) = await harness.launch()
        await stop(task)
        harness.network.clearRequests()
        harness.clock.advance(by: 3600)
        #expect(harness.network.urls.isEmpty)
        #expect(harness.controller.phase == .ready)
    }
}
