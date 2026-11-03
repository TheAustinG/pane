import PaneCore
import SwiftUI

enum StormFocus: Hashable {
    case timeline
    case alert(Int)
    case detail(Int)
}

/// Radar over the whole screen with the weather strip floating on it. Shown in place of the
/// dashboard layout while `AppModel.isStormTakeoverShown`.
struct StormTakeover: View {
    let model: AppModel
    let date: Date
    @State private var player = RadarPlayer()
    @State private var isDetailShown = false
    @State private var detailOrigin = 0
    @FocusState private var focus: StormFocus?

    private var alerts: [WeatherAlertInfo] { model.storm.state.alerts }

    private var defaultFocus: StormFocus { alerts.isEmpty ? .timeline : .alert(0) }

    var body: some View {
        ZStack {
            RadarBackdrop(radar: model.radar, player: player)
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            Group {
                switch model.settings.stormLayout {
                case .side: sideLayout
                case .bottom: bottomLayout
                }
            }
            .disabled(isDetailShown)
            if isDetailShown {
                StormAlertDetail(alerts: alerts, markImageData: model.weather.markImageData, focus: $focus) { closeDetail() }
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .environment(\.glassShade, 0.28)
        .animation(Theme.Motion.state, value: isDetailShown)
        .defaultFocus($focus, defaultFocus)
        .onExitCommand {
            if isDetailShown {
                closeDetail()
            } else {
                model.closeStormTakeover()
            }
        }
        .task { await model.radar.run() }
        .task {
            // The focus engine often picks the timeline over `defaultFocus` as the takeover replaces
            // the dashboard.
            try? await Task.sleep(for: .milliseconds(600))
            if focus == nil || focus == .timeline { focus = defaultFocus }
        }
        .onChange(of: model.isDebugMenuPresented) { _, presented in
            if !presented { focus = isDetailShown ? .detail(0) : defaultFocus }
        }
        .onChange(of: alerts.map(\.id)) { _, ids in
            if ids.isEmpty { isDetailShown = false }
            if focus == nil || !isValid(focus) { focus = defaultFocus }
        }
    }

    private func isValid(_ focus: StormFocus?) -> Bool {
        switch focus {
        case .alert(let index): !isDetailShown && alerts.indices.contains(index)
        case .detail(let index): isDetailShown && alerts.indices.contains(index)
        case .timeline: !isDetailShown
        case nil: false
        }
    }

    private func openDetail(from index: Int) {
        detailOrigin = index
        isDetailShown = true
        focus = .detail(index)
    }

    private func closeDetail() {
        isDetailShown = false
        focus = alerts.indices.contains(detailOrigin) ? .alert(detailOrigin) : defaultFocus
    }

    private var timeline: some View {
        RadarTimelineBar(radar: model.radar, player: player, timeZone: model.calendar.timeZone)
            .focused($focus, equals: .timeline)
    }

    private func alertButton(_ index: Int, stacked: Bool, meta: String) -> some View {
        Button { openDetail(from: index) } label: {
            AlertBanner(
                tone: .warning,
                title: alerts[index].summary,
                meta: meta,
                qrURL: alerts[index].detailsURL,
                stacked: stacked,
                identifier: "storm.alert.\(index)"
            )
        }
        .buttonStyle(GlassPaneButtonStyle())
        .focused($focus, equals: .alert(index))
        .accessibilityIdentifier("storm.alert.\(index)")
    }

    private var sideLayout: some View {
        HStack(alignment: .bottom, spacing: Theme.Layout.gutter) {
            timeline
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .focusSection()
            VStack(spacing: Theme.Layout.gutter) {
                StormConditions(model: model, date: date, layout: .side)
                    .padding(Theme.Layout.paneInset)
                    .frame(width: Theme.Layout.stormColumnWidth, alignment: .leading)
                    .glassPane()
                ScrollView {
                    VStack(spacing: Theme.Layout.gutter) {
                        ForEach(alerts.indices, id: \.self) { index in
                            alertButton(index, stacked: true, meta: alerts[index].meta)
                                .frame(width: Theme.Layout.stormColumnWidth)
                        }
                    }
                }
                .scrollClipDisabled()
                .frame(width: Theme.Layout.stormColumnWidth)
            }
        }
        .padding(.vertical, Theme.Layout.marginVertical)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
    }

    private var bottomLayout: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.gutter) {
            Spacer(minLength: 0)
            timeline
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
            HStack(spacing: 0) {
                StormConditions(model: model, date: date, layout: .bottom)
                    .frame(width: 470, alignment: .leading)
                Divider().overlay(Theme.Ink.rule).padding(.vertical, Theme.Space.s)
                if alerts.isEmpty {
                    StormNote(model: model, date: date, large: true)
                        .padding(.horizontal, Theme.Space.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    alertButton(0, stacked: false, meta: bottomMeta)
                        .padding(.horizontal, Theme.Space.l)
                        .frame(maxWidth: .infinity)
                }
                Divider().overlay(Theme.Ink.rule).padding(.vertical, Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.s) {
                    Spacer(minLength: 0)
                    if !alerts.isEmpty { StormNote(model: model, date: date, large: false) }
                    StormMark(model: model)
                }
                .padding(.leading, Theme.Space.l)
                .frame(width: 280, alignment: .trailing)
            }
            .padding(.horizontal, Theme.Layout.paneInset.leading)
            .padding(.vertical, Theme.Space.xxs)
            .frame(minHeight: Theme.Layout.stormStripHeight)
            .fixedSize(horizontal: false, vertical: true)
            .glassPane()
        }
        .padding(.vertical, Theme.Layout.marginVertical)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
    }

    private var bottomMeta: String {
        let extra = alerts.count - 1
        let hint = extra > 0 ? "\(extra) more \(extra == 1 ? "alert" : "alerts"). Click to see all." : "Click for details."
        return "\(alerts[0].meta). \(hint)"
    }
}

/// Compact clock, current conditions and, in the side column, the note and the Apple Weather mark.
private struct StormConditions: View {
    let model: AppModel
    let date: Date
    let layout: StormLayout

    var body: some View {
        let clock = ClockStrings(date: date, calendar: model.calendar)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            DashboardClock(time: clock.time, meridiem: clock.meridiem, date: clock.date, compact: true)
            if let display = display {
                HStack(spacing: Theme.Space.m) {
                    WeatherGlyph(symbol: display.now.symbolName, size: 64)
                    Text(display.now.temperature).font(.system(size: 72, weight: .thin))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(display.now.condition).font(Theme.Typeface.bodyStrong)
                        Text("H \(display.now.high)   L \(display.now.low)")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.Ink.secondary)
                    }
                    .lineLimit(1)
                }
            } else {
                Text("Weather unavailable")
                    .font(Theme.Typeface.callout)
                    .foregroundStyle(Theme.Ink.secondary)
                    .padding(.vertical, Theme.Space.s)
            }
            if layout == .side, display != nil {
                Rectangle().fill(Theme.Ink.rule).frame(height: 1)
                HStack(alignment: .bottom, spacing: Theme.Space.m) {
                    StormNote(model: model, date: date, large: false)
                    Spacer(minLength: 0)
                    StormMark(model: model)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storm.conditions")
    }

    private var display: WeatherDisplay? {
        model.weather.report.map { WeatherDisplay(report: $0, at: date, calendar: model.calendar) }
    }
}

/// The weather note, such as when rain starts, and how old the data is when it is not fresh.
private struct StormNote: View {
    let model: AppModel
    let date: Date
    let large: Bool

    var body: some View {
        if let report = model.weather.report {
            let note = WeatherDisplay(report: report, at: date, calendar: model.calendar).note
            VStack(alignment: large ? .leading : .trailing, spacing: Theme.Space.xxs) {
                if let note {
                    Label(note.text, systemImage: note.symbolName)
                        .font(large ? Theme.Typeface.title : Theme.Typeface.callout)
                        .multilineTextAlignment(large ? .leading : .trailing)
                        .accessibilityIdentifier("storm.note")
                }
                if let freshness = model.weather.freshness.label {
                    StaleNote(text: freshness)
                }
            }
        }
    }
}

private struct StormMark: View {
    let model: AppModel

    var body: some View {
        if model.weather.report != nil {
            AppleWeatherMark(imageData: model.weather.markImageData)
        }
    }
}
