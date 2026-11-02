#if DEBUG
import SwiftUI

/// The approved dashboard composition with synthetic data, built from the design system so the
/// layout shell can be checked against the mockup before the real cards exist.
struct DashboardSample: View {
    let scene: ScenePreset
    var particles = true
    var focus: FocusState<String?>.Binding

    var body: some View {
        ZStack {
            PreviewSky(scene: scene, particles: particles)
            VStack(spacing: Theme.Layout.gutter) {
                HStack(alignment: .top, spacing: Theme.Layout.gutter) {
                    ClockBlock(scene: scene)
                    Spacer(minLength: 0)
                    pane("weather", width: Theme.Layout.weatherWidth, height: Theme.Layout.topRowHeight) {
                        CurrentWeatherContent(scene: scene)
                    }
                }
                HStack(spacing: Theme.Layout.gutter) {
                    pane("forecast", width: Theme.Layout.forecastWidth, height: Theme.Layout.bottomRowHeight) {
                        ForecastContent(scene: scene)
                    }
                    pane("home", width: Theme.Layout.sideCardWidth, height: Theme.Layout.bottomRowHeight) {
                        HomeContent()
                    }
                    pane("github", width: Theme.Layout.sideCardWidth, height: Theme.Layout.bottomRowHeight) {
                        CodeContent(accent: scene.accentColor)
                    }
                }
            }
            .padding(.vertical, Theme.Layout.marginVertical)
            .padding(.horizontal, Theme.Layout.marginHorizontal)
        }
        .environment(\.glassShade, scene.glassShade)
    }

    private func pane<Content: View>(
        _ id: String,
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {} label: {
            content()
                .padding(Theme.Layout.paneInset)
                .frame(width: width, height: height, alignment: .topLeading)
        }
        .buttonStyle(GlassPaneButtonStyle())
        .focused(focus, equals: id)
        .accessibilityIdentifier("preview.pane.\(id)")
    }
}

struct ClockBlock: View {
    let scene: ScenePreset
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 20) {
            HStack(alignment: .firstTextBaseline, spacing: compact ? 10 : 18) {
                Text(scene.time)
                    .font(compact ? .system(size: 112, weight: .thin) : Theme.Typeface.clock)
                    .tracking(compact ? -3 : -8)
                Text(scene.meridiem)
                    .font(compact ? .system(size: 36, weight: .light) : Theme.Typeface.meridiem)
                    .opacity(0.9)
            }
            .padding(.top, compact ? 0 : -40)
            Text(scene.date)
                .font(compact ? Theme.Typeface.callout : Theme.Typeface.date)
                .opacity(0.92)
        }
        .lineLimit(1)
        .shadow(color: Theme.Glass.textShadow, radius: 15, y: 2)
        .accessibilityElement(children: .combine)
    }
}

private struct CurrentWeatherContent: View {
    let scene: ScenePreset

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.l) {
                WeatherGlyph(symbol: scene.symbol, size: 104)
                Text(scene.temp)
                    .font(Theme.Typeface.heroTemp)
                    .tracking(-4)
            }
            .frame(height: 112)
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(scene.condition).font(Theme.Typeface.title)
                Text("H \(scene.high)   L \(scene.low)")
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            Spacer(minLength: Theme.Space.s)
            Label(scene.note, systemImage: scene.noteSymbol)
                .font(Theme.Typeface.callout)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            DaylightArc(
                fraction: scene.arcFraction,
                sunrise: "6:23 AM",
                sunset: "4:45 PM",
                caption: scene.arcCaption
            )
        }
    }
}

private struct ForecastContent: View {
    let scene: ScenePreset

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                PaneHeading(text: "Next 6 hours")
                Spacer()
                WeatherMarkPlaceholder()
            }
            HStack(spacing: 0) {
                ForEach(Array(scene.hourly.enumerated()), id: \.offset) { _, hour in
                    VStack(spacing: Theme.Space.xxs) {
                        Text(hour.label)
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Ink.secondary)
                        WeatherGlyph(symbol: hour.symbol, size: 44)
                        Text(hour.temp).font(Theme.Typeface.metric)
                        PrecipChance(percent: hour.pop)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                }
            }
            Rectangle().fill(Theme.Ink.rule).frame(height: 1)
            PaneHeading(text: "This week")
            HStack(spacing: 0) {
                ForEach(ScenePreset.daily, id: \.label) { day in
                    VStack(spacing: Theme.Space.xxs) {
                        Text(day.label)
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Ink.secondary)
                        WeatherGlyph(symbol: day.symbol, size: 40)
                        HStack(spacing: 8) {
                            Text(day.high).fontWeight(.medium)
                            Text(day.low).foregroundStyle(Theme.Ink.tertiary)
                        }
                        .font(Theme.Typeface.callout.monospacedDigit())
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                }
            }
        }
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

struct HomeContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            PaneHeading(text: "Home", symbol: "house")
            VStack(alignment: .leading, spacing: 0) {
                StatusRow(symbol: "thermometer.medium", title: "70° inside", detail: "Heating to 69°")
                Spacer(minLength: 0)
                StatusRow(symbol: "humidity", title: "31% humidity", detail: "Bedroom 33%") {
                    NudgeChip(text: "Dry air")
                }
                Spacer(minLength: 0)
                StatusRow(symbol: "lock", title: "Front door locked", detail: "Since 3:58 PM")
                Spacer(minLength: 0)
                StatusRow(symbol: "lightbulb", title: "3 lights on", detail: "Kitchen, Living Room, Hall")
                Spacer(minLength: 0)
                StatusRow(symbol: "person.2", title: "Everyone's home") {
                    HStack(spacing: -10) {
                        Avatar(text: "A", fill: 0.28)
                        Avatar(text: "+1", fill: 0.2)
                    }
                }
            }
        }
    }
}

private struct Avatar: View {
    let text: String
    let fill: Double

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 40, height: 40)
            .background(.white.opacity(fill), in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2) }
    }
}

struct CodeContent: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeading(text: "GitHub", symbol: "arrow.triangle.branch")
            Spacer(minLength: Theme.Space.s)
            HStack {
                Label {
                    Text("12-day streak")
                } icon: {
                    Image(systemName: "flame").foregroundStyle(Theme.Signal.nudge)
                }
                .font(Theme.Typeface.headline)
                Spacer(minLength: Theme.Space.s)
                Text("4 today")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            ContributionGrid(levels: ScenePreset.contributionLevels, accent: accent)
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xs) {
                    Text("pane").font(Theme.Typeface.subheadStrong)
                    Text("2h ago")
                        .font(Theme.Typeface.subhead)
                        .foregroundStyle(Theme.Ink.tertiary)
                }
                Text("Tune glass pane focus lift")
                    .font(Theme.Typeface.subhead)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            NudgeChip(text: "pane image built 3h ago, not redeployed", symbol: "shippingbox")
        }
    }
}
#endif
