import Observation
import PaneCore

/// Playback position of the radar loop over the frames that are ready.
@MainActor
@Observable
final class RadarPlayer {
    private(set) var loop = RadarLoop()
    var isPaused = false

    /// The loop index kept inside `count`, since frames arrive while the loop already runs.
    func shownIndex(count: Int) -> Int? {
        count > 0 ? min(loop.index, count - 1) : nil
    }

    func run(over radar: RadarController) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: loop.delay(frameCount: radar.readyFrames.count))
            guard !Task.isCancelled else { return }
            loop.advance(frameCount: radar.readyFrames.count)
        }
    }
}
