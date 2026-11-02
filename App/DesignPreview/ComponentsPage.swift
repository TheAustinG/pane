#if DEBUG
import SwiftUI

struct ComponentsPage: View {
    var focus: FocusState<String?>.Binding

    private let glyphs = [
        "sun.max", "moon.stars", "cloud.sun", "cloud.moon", "cloud", "cloud.rain",
        "cloud.heavyrain", "cloud.bolt.rain", "cloud.snow", "cloud.sleet", "cloud.fog", "wind",
    ]

    var body: some View {
        ZStack {
            PreviewSky(scene: .golden)
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HStack(alignment: .top, spacing: Theme.Layout.gutter) {
                    sample("Pane at rest") {
                        paneBody.glassPane()
                    }
                    sample("Pane focused: lift, sheen, rim") {
                        paneBody.glassPane(focused: true)
                    }
                    sample("Live pane: move focus here") {
                        Button {} label: { paneBody }
                            .buttonStyle(GlassPaneButtonStyle())
                            .focused(focus, equals: "pane")
                            .accessibilityIdentifier("preview.components.pane")
                    }
                }
                HStack(alignment: .top, spacing: 56) {
                    sample("Scene buttons, native glass") {
                        HStack(spacing: Theme.Space.m) {
                            sceneButton("goodnight", "Goodnight", "moon.zzz")
                            sceneButton("movie", "Movie", "film")
                            sceneButton("morning", "Morning", "sun.horizon")
                            Button {} label: { Label("Away", systemImage: "figure.walk") }
                                .buttonStyle(.glass)
                                .disabled(true)
                        }
                    }
                    sample("Nudges") {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            HStack(spacing: Theme.Space.s) {
                                NudgeChip(text: "Dry air")
                                NudgeChip(text: "Front door unlocked", symbol: "lock.open")
                            }
                            NudgeChip(text: "pane image built 3h ago, not redeployed", symbol: "shippingbox")
                            NudgeChip(text: "Home Assistant offline, retrying", symbol: "wifi.exclamationmark", tone: .warning)
                        }
                    }
                }
                HStack(alignment: .top, spacing: Theme.Layout.gutter) {
                    sample("Weather alert, text as issued") {
                        AlertBanner(
                            tone: .warning,
                            title: "Severe Thunderstorm Warning",
                            meta: "National Weather Service, until 8:15 PM",
                            message: "Hazards include 60 mph wind gusts and penny size hail.",
                            qrURL: URL(string: "https://weatherkit.apple.com/alertDetails/index.html")
                        )
                        .frame(width: 900)
                        .glassPane()
                    }
                    sample("Status rows and stale data") {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            StatusRow(symbol: "lock", title: "Front door locked", detail: "Since 3:58 PM")
                            StatusRow(symbol: "humidity", title: "31% humidity", detail: "Bedroom 33%") {
                                NudgeChip(text: "Dry air")
                            }
                            StaleNote(text: "Updated 20 min ago")
                        }
                        .padding(Theme.Layout.paneInset)
                        .frame(width: 560, alignment: .leading)
                        .glassPane()
                    }
                }
                sample("Condition glyphs, SF Symbols Light") {
                    HStack(spacing: Theme.Space.l) {
                        ForEach(glyphs, id: \.self) { symbol in
                            WeatherGlyph(symbol: symbol, size: 56)
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Layout.marginVertical)
            .padding(.horizontal, Theme.Layout.marginHorizontal)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.glassShade, ScenePreset.golden.glassShade)
    }

    private var paneBody: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            PaneHeading(text: "Home", symbol: "house")
            StatusRow(symbol: "thermometer.medium", title: "70° inside", detail: "Heating to 69°")
        }
        .padding(Theme.Layout.paneInset)
        .frame(width: 520, height: 200, alignment: .topLeading)
    }

    private func sceneButton(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button {} label: { Label(title, systemImage: symbol) }
            .buttonStyle(.glass)
            .focused(focus, equals: id)
            .accessibilityIdentifier("preview.components.\(id)")
    }

    private func sample<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
                .shadow(color: Theme.Glass.textShadow, radius: 8, y: 1)
            content()
        }
    }
}
#endif
