import SwiftUI

struct CurrentWeatherCard: DashboardCard {
    let context: CardContext

    var body: some View {
        #if DEBUG
        if context.model.usesSampleFixtures {
            CurrentWeatherContent(scene: ScenePreset.matching(context.model.sceneOverride))
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        CardPlaceholder(heading: "Weather", line: "Waiting for weather")
    }
}

struct ForecastCard: DashboardCard {
    let context: CardContext

    var body: some View {
        #if DEBUG
        if context.model.usesSampleFixtures {
            ForecastContent(scene: ScenePreset.matching(context.model.sceneOverride))
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        CardPlaceholder(heading: "Forecast", line: "Forecast appears with live weather")
    }
}

#if DEBUG
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
#endif
