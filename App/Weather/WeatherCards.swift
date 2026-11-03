import PaneCore
import SwiftUI

struct CurrentWeatherCard: DashboardCard {
    let context: CardContext

    /// The Settings button stays hidden until focused, so with no location the card itself is the
    /// way in.
    static func activate(model: AppModel) {
        if model.weather.location == nil { model.isSettingsPresented = true }
    }

    var body: some View {
        let weather = context.model.weather
        if let report = weather.report {
            CurrentWeatherContent(
                display: WeatherDisplay(report: report, at: context.date, calendar: context.model.calendar),
                freshness: weather.freshness.label
            )
        } else {
            WeatherEmptyCard(heading: "Weather", model: context.model)
        }
    }
}

struct ForecastCard: DashboardCard {
    let context: CardContext

    var body: some View {
        let weather = context.model.weather
        if let report = weather.report {
            ForecastContent(
                display: WeatherDisplay(report: report, at: context.date, calendar: context.model.calendar),
                markImageData: weather.markImageData
            )
        } else {
            WeatherEmptyCard(heading: "Forecast", model: context.model)
        }
    }
}

private struct WeatherEmptyCard: View {
    let heading: String
    let model: AppModel

    var body: some View {
        CardPlaceholder(heading: heading, line: line, lineIdentifier: "weather.empty")
    }

    private var line: String {
        if model.weather.location == nil { return "Set your location in Settings" }
        if model.weather.lastFailure != nil { return "Weather unavailable, trying again soon" }
        return "Loading weather"
    }
}

private struct CurrentWeatherContent: View {
    let display: WeatherDisplay
    let freshness: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.l) {
                WeatherGlyph(symbol: display.now.symbolName, size: 104)
                Text(display.now.temperature)
                    .font(Theme.Typeface.heroTemp)
                    .tracking(-4)
                    .accessibilityIdentifier("weather.temperature")
            }
            .frame(height: 112)
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(display.now.condition)
                    .font(Theme.Typeface.title)
                    .accessibilityIdentifier("weather.condition")
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                    Text("H \(display.now.high)   L \(display.now.low)")
                        .font(Theme.Typeface.body)
                        .foregroundStyle(Theme.Ink.secondary)
                    Spacer(minLength: 0)
                    if let freshness {
                        StaleNote(text: freshness)
                            .lineLimit(1)
                            .accessibilityIdentifier("weather.freshness")
                    }
                }
            }
            Spacer(minLength: Theme.Space.s)
            noteRow
            Spacer(minLength: Theme.Space.s)
            DaylightArc(
                fraction: display.daylight.fraction,
                sunrise: display.daylight.sunrise,
                sunset: display.daylight.sunset,
                caption: display.daylight.caption
            )
        }
    }

    private var noteRow: some View {
        Label(display.note?.text ?? " ", systemImage: display.note?.symbolName ?? "umbrella")
            .font(Theme.Typeface.callout)
            .lineLimit(1)
            .opacity(display.note == nil ? 0 : 1)
            .accessibilityHidden(display.note == nil)
            .frame(height: Self.noteHeight, alignment: .leading)
            .accessibilityIdentifier("weather.note")
    }

    private static let noteHeight: CGFloat = 34
}

private struct ForecastContent: View {
    let display: WeatherDisplay
    let markImageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                PaneHeading(text: "Next 6 hours")
                Spacer()
                AppleWeatherMark(imageData: markImageData)
            }
            HStack(spacing: 0) {
                ForEach(Array(display.hours.enumerated()), id: \.offset) { _, hour in
                    VStack(spacing: Theme.Space.xxs) {
                        Text(hour.label)
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Ink.secondary)
                        WeatherGlyph(symbol: hour.symbolName, size: 44)
                        Text(hour.temperature).font(Theme.Typeface.metric)
                        PrecipChance(percent: hour.precipitationPercent)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                }
            }
            Rectangle().fill(Theme.Ink.rule).frame(height: 1)
            PaneHeading(text: "This week")
            HStack(spacing: 0) {
                ForEach(Array(display.days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: Theme.Space.xxs) {
                        Text(day.label)
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Ink.secondary)
                        WeatherGlyph(symbol: day.symbolName, size: 40)
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
