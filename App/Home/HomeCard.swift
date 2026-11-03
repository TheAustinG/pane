import PaneCore
import SwiftUI

struct HomeCard: DashboardCard {
    let context: CardContext

    static func activate(model: AppModel) {
        model.isHomeScenesPresented = true
    }

    var body: some View {
        let home = context.model.home
        HomeContent(summary: home.summary, connection: home.connection, calendar: context.model.calendar, now: context.date)
    }
}

/// Where each nudge chip sits: on the row whose reading raised it. Bedroom TV has no row of its own
/// on the card, so it joins the people row.
private enum HomeRow: String, CaseIterable {
    case climate, humidity, lock, lights, people

    var nudges: [HomeNudgeKind] {
        switch self {
        case .climate: []
        case .humidity: [.dryAir, .humidAir]
        case .lock: [.doorUnlockedLate]
        case .lights: [.lightsOnAway]
        case .people: [.bedroomTVLate]
        }
    }
}

private struct HomeContent: View {
    let summary: HomeSummary
    let connection: HomeConnection
    let calendar: Calendar
    let now: Date

    private var visibleRows: [HomeRow] {
        HomeRow.allCases.filter { row in
            switch row {
            case .climate: summary.climate != nil
            case .humidity: !summary.humidity.isEmpty
            case .lock: summary.lock != nil
            case .lights: !summary.lights.isEmpty
            case .people: !summary.people.isEmpty
            }
        }
    }

    var body: some View {
        let rows = visibleRows
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            header
            if rows.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                        if index > 0 { Spacer(minLength: 0) }
                        content(for: row)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("home.row.\(row.rawValue)")
                    }
                }
                .opacity(connection.isConnected ? 1 : 0.62)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Home connection")
                .accessibilityValue(connection.stateName)
                .accessibilityIdentifier("home.connection")
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            PaneHeading(text: "Home", symbol: "house")
            Spacer(minLength: 0)
            switch connection {
            case .disconnected:
                NudgeChip(text: "Reconnecting", symbol: "wifi.exclamationmark", tone: .warning)
                    .accessibilityIdentifier("home.warning")
            case .authFailed:
                NudgeChip(text: "Token rejected", symbol: "key.slash", tone: .warning)
                    .accessibilityIdentifier("home.warning")
            default:
                EmptyView()
            }
        }
        .frame(height: 30)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch connection {
        case .notConfigured:
            line("Set up in Settings")
        case .connecting:
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text("Connecting").font(Theme.Typeface.body).foregroundStyle(Theme.Ink.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.state")
        case .disconnected:
            line("Cannot reach Home Assistant")
        case .authFailed:
            line("Update the token in Settings")
        case .connected:
            line("Pick the entities to show in Settings")
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.Ink.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("home.state")
    }

    @ViewBuilder
    private func content(for row: HomeRow) -> some View {
        switch row {
        case .climate: climateRow(summary.climate!)
        case .humidity: humidityRow(summary.humidity)
        case .lock: lockRow(summary.lock!)
        case .lights: lightsRow(summary.lights)
        case .people: peopleRow(summary.people)
        }
    }

    private func chips(_ row: HomeRow) -> [HomeNudgeKind] {
        row.nudges.filter { summary.nudge($0) != nil }
    }

    private func chipStack(_ kinds: [HomeNudgeKind]) -> some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(kinds, id: \.self) { kind in
                NudgeChip(text: kind.chipText)
                    .accessibilityIdentifier("home.nudge.\(kind.rawValue)")
            }
        }
    }

    /// The chips trail the row when they fit beside its text. Otherwise they replace the detail line,
    /// which keeps the row shorter than stacking them under it.
    private func statusRow(
        _ row: HomeRow,
        symbol: String,
        title: String,
        detail: String?,
        trailing: AnyView = AnyView(EmptyView())
    ) -> some View {
        let kinds = chips(row)
        if kinds.isEmpty {
            return AnyView(StatusRow(symbol: symbol, title: title, detail: detail) { trailing })
        }
        return AnyView(ViewThatFits(in: .horizontal) {
            StatusRow(symbol: symbol, title: title, detail: detail) {
                HStack(spacing: Theme.Space.s) {
                    chipStack(kinds)
                    trailing
                }
            }
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .regular))
                    .frame(width: Theme.Layout.iconWell, height: Theme.Layout.iconWell)
                    .background(Theme.Ink.well, in: Circle())
                    .accessibilityHidden(true)
                    .padding(.trailing, Theme.Space.m)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                    chipStack(kinds)
                }
                Spacer(minLength: Theme.Space.s)
                trailing
            }
        })
    }

    private func climateRow(_ climate: HomeSummary.Climate) -> some View {
        let title: String
        if !climate.isUnavailable, let inside = climate.insideTemperature {
            title = "\(Int(inside.rounded()))° inside"
        } else {
            title = "Thermostat unavailable"
        }
        // Four stacked chips overrun the pane; the thermostat detail is the line the card can spare.
        let detail = summary.nudges.count >= 4 ? nil : climateDetail(climate)
        return StatusRow(symbol: "thermometer.medium", title: title, detail: detail)
    }

    private func climateDetail(_ climate: HomeSummary.Climate) -> String? {
        guard !climate.isUnavailable else { return nil }
        func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }
        if climate.mode == "off" { return "Off" }
        var target = climate.targetTemperature.map(degrees)
        if target == nil, let low = climate.targetLow, let high = climate.targetHigh {
            target = "\(degrees(low)) to \(degrees(high))"
        }
        switch (climate.action, target) {
        case ("heating", let target?): return "Heating to \(target)"
        case ("cooling", let target?): return "Cooling to \(target)"
        case ("heating", nil): return "Heating"
        case ("cooling", nil): return "Cooling"
        case (_, let target?): return "Set to \(target)"
        default: return nil
        }
    }

    private func humidityRow(_ readings: [HomeSummary.Reading]) -> some View {
        let main = readings[0]
        let detail = readings.count > 1
            ? readings.dropFirst().map { "\(Self.shortName($0.name)) \(Self.percent($0.percent))" }.joined(separator: ", ")
            : Self.shortName(main.name)
        return statusRow(
            .humidity,
            symbol: "humidity",
            title: main.percent.map { "\(Int($0.rounded()))% humidity" } ?? "Humidity unavailable",
            detail: detail
        )
    }

    private func lockRow(_ lock: HomeSummary.Lock) -> some View {
        let unlocked = lock.state == "unlocked" || lock.state == "open"
        return statusRow(
            .lock,
            symbol: unlocked ? "lock.open" : "lock",
            title: "\(lock.name) \(lock.state.replacingOccurrences(of: "_", with: " "))",
            detail: lock.since.map { "Since \(sinceText($0))" }
        )
    }

    private func lightsRow(_ lights: [HomeSummary.Light]) -> some View {
        let on = lights.filter(\.isOn)
        return statusRow(
            .lights,
            symbol: on.isEmpty ? "lightbulb.slash" : "lightbulb",
            title: on.isEmpty ? "Lights off" : "\(on.count) \(on.count == 1 ? "light" : "lights") on",
            detail: on.isEmpty ? nil : on.map(\.name).joined(separator: ", ")
        )
    }

    private func peopleRow(_ people: [HomeSummary.Person]) -> some View {
        let home = people.filter(\.isHome)
        let title: String
        var detail: String?
        switch (people.count, home.count) {
        case (1, 1): title = "\(people[0].name) is home"
        case (1, _): title = "\(people[0].name) is away"
        case (_, people.count): title = "Everyone's home"
        case (_, 0): title = "Nobody home"
        default:
            title = "\(home.count) of \(people.count) home"
            detail = "Away: \(people.filter { !$0.isHome }.map(\.name).joined(separator: ", "))"
        }
        return statusRow(.people, symbol: "person.2", title: title, detail: detail, trailing: AnyView(avatars(people)))
    }

    private func avatars(_ people: [HomeSummary.Person]) -> some View {
        let shown = people.prefix(people.count > 4 ? 3 : 4)
        return HStack(spacing: -10) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, person in
                Avatar(text: String(person.name.prefix(1)).uppercased(), isHome: person.isHome)
            }
            if people.count > shown.count {
                Avatar(text: "+\(people.count - shown.count)", isHome: true)
            }
        }
        .accessibilityHidden(true)
    }

    private func sinceText(_ date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "en_US")))
        guard !calendar.isDate(date, inSameDayAs: now) else { return time }
        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        return "\(weekday) \(time)"
    }

    private static func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "n/a"
    }

    /// "Bedroom Humidity" reads better as "Bedroom" beside its reading.
    private static func shortName(_ name: String) -> String {
        let trimmed = name.replacingOccurrences(of: " humidity", with: "", options: [.caseInsensitive, .anchored, .backwards])
        return trimmed.isEmpty ? name : trimmed
    }
}

private struct Avatar: View {
    let text: String
    let isHome: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(isHome ? Theme.Ink.primary : Theme.Ink.secondary)
            .frame(width: 40, height: 40)
            .background(.white.opacity(isHome ? 0.28 : 0.1), in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(isHome ? 0.5 : 0.3), lineWidth: 2) }
    }
}
