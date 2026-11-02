#if DEBUG
import SwiftUI

struct ClockBlock: View {
    let scene: ScenePreset
    var compact = false

    var body: some View {
        DashboardClock(time: scene.time, meridiem: scene.meridiem, date: scene.date, compact: compact)
    }
}

/// Stands where the Apple Weather mark goes. The real mark is the image WeatherKit's attribution
/// returns, loaded at runtime.
struct WeatherMarkPlaceholder: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "applelogo")
            Text("Weather")
        }
        .font(Theme.Typeface.caption.weight(.medium))
        .foregroundStyle(Theme.Ink.tertiary)
        .accessibilityLabel("Apple Weather")
    }
}
#endif
