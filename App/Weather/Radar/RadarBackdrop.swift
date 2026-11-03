import PaneCore
import SwiftUI

/// The radar map filling the screen, and the loop that flips its frames.
struct RadarBackdrop: View {
    let radar: RadarController
    let player: RadarPlayer
    @State private var revision = 0

    var body: some View {
        Group {
            if let viewport = radar.viewport {
                map(viewport: viewport)
            } else {
                Color.black
            }
        }
        .task {
            while !Task.isCancelled {
                if revision != radar.revision { revision = radar.revision }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        .task(id: player.isPaused) {
            guard !player.isPaused else { return }
            await player.run(over: radar)
        }
        .accessibilityHidden(true)
    }

    private func map(viewport: RadarViewport) -> some View {
        let frames = radar.readyFrames
        let index = player.shownIndex(count: frames.count)
        return RadarMapView(
            bounds: viewport.bounds,
            tiles: radar.tiles,
            revision: revision,
            store: radar.store,
            frame: index.map { frames[$0].id },
            nextFrame: index.map { frames[($0 + 1) % frames.count].id }
        )
    }
}
