#if DEBUG
import SwiftUI

struct TypePage: View {
    private let roles: [(String, Font, String, Bool)] = [
        ("Date, 52 Regular", Theme.Typeface.date, "Sunday, November 1", false),
        ("Screen title, 52 Semibold", Theme.Typeface.screenTitle, "Connect Home Assistant", false),
        ("Title, 40 Medium", Theme.Typeface.title, "Partly Cloudy", false),
        ("Headline, 36 Semibold", Theme.Typeface.headline, "12-day streak", false),
        ("Metric, 32 Medium, tabular", Theme.Typeface.metric, "47°  46°  45°", false),
        ("Body, 30 Regular and Medium", Theme.Typeface.body, "H 58°   L 41°", false),
        ("Callout, 28 Regular", Theme.Typeface.callout, "Rain likely after 9 PM", false),
        ("Subhead, 26 Regular", Theme.Typeface.subhead, "Tune glass pane focus lift", false),
        ("Caption, 24 Regular", Theme.Typeface.caption, "Sunrise 6:23 AM", false),
        ("Label, 24 Semibold, tracked", Theme.Typeface.label, "NEXT 6 HOURS", true),
    ]

    var body: some View {
        ZStack {
            PreviewSky(scene: .rain, particles: false)
            HStack(alignment: .top, spacing: 72) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    specimenLabel("Clock, 300 Thin, -8 tracking; meridiem 64 Light")
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text("10:48").font(Theme.Typeface.clock).tracking(-8)
                        Text("PM").font(Theme.Typeface.meridiem).opacity(0.9)
                    }
                    .padding(.top, -40)
                    specimenLabel("Hero temperature, 132 Thin, -4 tracking")
                    Text("47°").font(Theme.Typeface.heroTemp).tracking(-4)
                    Spacer(minLength: 0)
                    specimenLabel("Spacing: 6, 10, 14, 18, 28, 32, 40. Pane corners 40, chips 20.")
                    HStack(alignment: .bottom, spacing: Theme.Space.m) {
                        ForEach([Theme.Space.xxs, Theme.Space.xs, Theme.Space.s, Theme.Space.m, Theme.Space.l, Theme.Space.xl, Theme.Space.xxl], id: \.self) { value in
                            Rectangle().fill(Theme.Ink.secondary).frame(width: value, height: value)
                        }
                        RoundedRectangle(cornerRadius: Theme.Glass.chipRadius, style: .continuous)
                            .strokeBorder(Theme.Ink.secondary, lineWidth: 2)
                            .frame(width: 120, height: 60)
                        RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius, style: .continuous)
                            .strokeBorder(Theme.Ink.secondary, lineWidth: 2)
                            .frame(width: 160, height: 100)
                    }
                }
                .frame(width: 820, alignment: .leading)
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(roles, id: \.0) { role in
                        VStack(alignment: .leading, spacing: 2) {
                            specimenLabel(role.0)
                            Text(role.2)
                                .font(role.1)
                                .tracking(role.3 ? Theme.Typeface.labelTracking : 0)
                                .foregroundStyle(role.3 ? Theme.Ink.tertiary : Theme.Ink.primary)
                        }
                    }
                }
                .padding(Theme.Layout.paneInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPane()
            }
            .padding(.vertical, Theme.Layout.marginVertical)
            .padding(.horizontal, Theme.Layout.marginHorizontal)
        }
        .environment(\.glassShade, ScenePreset.rain.glassShade)
    }

    private func specimenLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Ink.tertiary)
    }
}

struct PalettePage: View {
    private let ink: [(String, Color)] = [
        ("Ink 100%", Theme.Ink.primary), ("Ink 80%", Theme.Ink.secondary), ("Ink 72%", Theme.Ink.tertiary),
        ("Rule 20%", Theme.Ink.rule), ("Well 14%", Theme.Ink.well), ("Faint 10%", Theme.Ink.faint),
    ]
    private let signals: [(String, Color)] = [
        ("Rain chance", Theme.Signal.rain), ("Sun", Theme.Signal.sun), ("Nudge amber", Theme.Signal.nudge),
        ("Nudge ink", Theme.Signal.nudgeInk), ("Warning", Theme.Signal.warning),
    ]

    var body: some View {
        ZStack {
            PreviewSky(scene: .night, particles: false)
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HStack(alignment: .top, spacing: Theme.Layout.gutter) {
                    swatchPane("Ink on glass", ink)
                    swatchPane("Signals, each with one job", signals)
                }
                PaneHeading(text: "Scene anchors: sky by sun altitude, then condition overlays")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(408), spacing: Theme.Layout.gutter), count: 4), spacing: Theme.Space.l) {
                    ForEach(ScenePreset.all) { scene in
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            PreviewSky(scene: scene)
                                .frame(width: 408, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            HStack(spacing: Theme.Space.xs) {
                                Circle().fill(scene.accentColor).frame(width: 18, height: 18)
                                Text(scene.name).font(Theme.Typeface.bodyStrong)
                                Spacer()
                                Text("shade \(Int(scene.glassShade * 100))%")
                                    .font(Theme.Typeface.caption)
                                    .foregroundStyle(Theme.Ink.secondary)
                            }
                            .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Layout.marginVertical)
            .padding(.horizontal, Theme.Layout.marginHorizontal)
        }
        .environment(\.glassShade, ScenePreset.night.glassShade)
    }

    private func swatchPane(_ title: String, _ swatches: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            PaneHeading(text: title)
            HStack(spacing: Theme.Space.m) {
                ForEach(swatches, id: \.0) { swatch in
                    VStack(spacing: Theme.Space.xxs) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(swatch.1)
                            .frame(width: 112, height: 72)
                        Text(swatch.0)
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Ink.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(Theme.Layout.paneInset)
        .glassPane()
    }
}
#endif
