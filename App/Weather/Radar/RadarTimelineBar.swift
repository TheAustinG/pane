import PaneCore
import SwiftUI

/// The floating capsule under the radar: loop state, the shown frame's time, a tick per frame and
/// the data credit. Selecting it pauses or resumes the loop.
struct RadarTimelineBar: View {
    let radar: RadarController
    let player: RadarPlayer
    let timeZone: TimeZone

    var body: some View {
        Button {
            player.isPaused.toggle()
        } label: {
            HStack(spacing: Theme.Space.m) {
                content
                if let credit = radar.credit {
                    Text("Radar: \(credit)")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Ink.tertiary)
                        .lineLimit(1)
                        .accessibilityIdentifier("storm.radar.credit")
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .fixedSize()
        }
        .buttonStyle(GlassPaneButtonStyle())
        .accessibilityIdentifier("storm.timeline")
    }

    @ViewBuilder private var content: some View {
        let frames = radar.readyFrames
        if let index = player.shownIndex(count: frames.count) {
            Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 26)
            Text(timeLabel(frames[index].time))
                .font(Theme.Typeface.bodyStrong.monospacedDigit())
                .frame(minWidth: 128, alignment: .leading)
            HStack(spacing: 8) {
                ForEach(frames.indices, id: \.self) { tick in
                    Capsule()
                        .fill(tick == index ? Theme.Ink.primary : (tick < index ? Theme.Ink.secondary : Theme.Ink.rule))
                        .frame(width: tick == index ? 28 : 18, height: 8)
                }
            }
            Text("Now")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
        } else {
            Text(statusText)
                .font(Theme.Typeface.bodyStrong)
        }
    }

    private var statusText: String {
        if case .failed(let message) = radar.phase { message } else { "Loading radar" }
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
