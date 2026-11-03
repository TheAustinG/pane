import Foundation
import Testing
@testable import PaneCore

@Suite("Radar tile store")
struct RadarTileStoreTests {
    private let a = TileCoordinate(z: 9, x: 131, y: 190)
    private let b = TileCoordinate(z: 9, x: 132, y: 190)

    @Test func storedAndEmptyTilesAreResolvedButOnlyStoredOnesHoldBytes() {
        let store = RadarTileStore()
        #expect(!store.isResolved(frame: "f1", tile: a))
        store.insert(RadarFixture.png, frame: "f1", tile: a)
        store.markEmpty(frame: "f1", tile: b)
        #expect(store.data(frame: "f1", tile: a) == RadarFixture.png)
        #expect(store.contains(frame: "f1", tile: a))
        #expect(store.isResolved(frame: "f1", tile: b))
        #expect(store.data(frame: "f1", tile: b) == nil)
        #expect(!store.contains(frame: "f1", tile: b))
        #expect(!store.isResolved(frame: "f2", tile: a))
        #expect(store.byteCount == RadarFixture.png.count)
    }

    @Test func keepDropsRolledOffFramesAndTilesOutsideTheLayout() {
        let store = RadarTileStore()
        for frame in ["f1", "f2", "f3"] {
            store.insert(RadarFixture.png, frame: frame, tile: a)
            store.markEmpty(frame: frame, tile: b)
        }
        store.keep(frames: ["f2", "f3"])
        #expect(!store.isResolved(frame: "f1", tile: a))
        #expect(!store.isResolved(frame: "f1", tile: b))
        #expect(store.isResolved(frame: "f2", tile: b))

        store.keep(frames: ["f2", "f3"], tiles: [b])
        #expect(!store.contains(frame: "f2", tile: a))
        #expect(store.isResolved(frame: "f3", tile: b))
        #expect(store.byteCount == 0)
    }

    @Test func concurrentReadersAndWritersAgree() async {
        let store = RadarTileStore()
        await withTaskGroup(of: Void.self) { group in
            for x in 0..<200 {
                group.addTask {
                    let tile = TileCoordinate(z: 9, x: x, y: 0)
                    store.insert(RadarFixture.png, frame: "f", tile: tile)
                    _ = store.data(frame: "f", tile: tile)
                }
            }
        }
        #expect((0..<200).allSatisfy { store.contains(frame: "f", tile: TileCoordinate(z: 9, x: $0, y: 0)) })
        #expect(store.byteCount == 200 * RadarFixture.png.count)
    }
}

@Suite("Radar loop")
struct RadarLoopTests {
    @Test func playsEachFrameThenHoldsTheNewest() {
        var loop = RadarLoop()
        var shown: [Int] = []
        var delays: [Duration] = []
        for _ in 0..<8 {
            shown.append(loop.index)
            delays.append(loop.delay(frameCount: 4))
            loop.advance(frameCount: 4)
        }
        #expect(shown == [0, 1, 2, 3, 0, 1, 2, 3])
        let frame = RadarLoop.frameDuration
        let hold = RadarLoop.newestHold
        #expect(delays == [frame, frame, frame, hold, frame, frame, frame, hold])
    }

    @Test func aSingleFrameHoldsAndNoFramesResets() {
        var loop = RadarLoop(index: 5)
        #expect(loop.delay(frameCount: 1) == RadarLoop.newestHold)
        loop.advance(frameCount: 0)
        #expect(loop.index == 0)
        loop.advance(frameCount: 1)
        #expect(loop.index == 0)
    }

    @Test func fewerFramesWrapBackToTheOldest() {
        var loop = RadarLoop(index: 10)
        loop.advance(frameCount: 12)
        #expect(loop.index == 11)
        #expect(loop.delay(frameCount: 12) == RadarLoop.newestHold)
        loop.advance(frameCount: 12)
        #expect(loop.index == 0)

        var shrunk = RadarLoop(index: 11)
        #expect(shrunk.delay(frameCount: 3) == RadarLoop.newestHold)
        shrunk.advance(frameCount: 3)
        #expect(shrunk.index == 0)
    }
}
