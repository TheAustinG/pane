import PaneCore
import SwiftUI

/// Night dim schedule and the manual Dim now toggle.
enum NightSettingsSection: SettingsSection {
    static let title = "Night"

    static func rows(model: AppModel) -> some View {
        NightSettingsRows(model: model)
    }

    static let startChoices = clockTimes(from: 21 * 60, through: 25 * 60)
    static let endChoices = clockTimes(from: 5 * 60, through: 9 * 60)

    private static func clockTimes(from first: Int, through last: Int) -> [ClockTime] {
        stride(from: first, through: last, by: 30).map { ClockTime(hour: ($0 / 60) % 24, minute: $0 % 60) }
    }
}

private struct NightSettingsRows: View {
    let model: AppModel

    var body: some View {
        let settings = Bindable(model.settings)
        Toggle("Night dim", isOn: settings.nightSchedule.isEnabled)
            .settingsHelp("The dashboard dims to about 30 percent overnight.")
            .accessibilityIdentifier("settings.night.enabled")
        timePicker(
            "Starts",
            selection: settings.nightSchedule.start,
            choices: NightSettingsSection.startChoices,
            help: "When the dashboard dims for the night.",
            id: "settings.night.start"
        )
        timePicker(
            "Ends",
            selection: settings.nightSchedule.end,
            choices: NightSettingsSection.endChoices,
            help: "When the dashboard returns to full brightness in the morning.",
            id: "settings.night.end"
        )
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            dimNowRow
        }
    }

    private func timePicker(
        _ title: String,
        selection: Binding<ClockTime>,
        choices: [ClockTime],
        help: String,
        id: String
    ) -> some View {
        let options = choices.contains(selection.wrappedValue) ? choices : [selection.wrappedValue] + choices
        return SettingsChoiceRow(title: title, help: help, options: options, selection: selection, label: \.label)
            .accessibilityIdentifier(id)
    }

    private var dimNowRow: some View {
        let now = model.now()
        let schedule = model.settings.nightSchedule
        let current = model.settings.nightDimOverride
        let isDimmed = NightDim.isDimmed(at: now, schedule: schedule, override: current, calendar: model.calendar)
        return SettingsValueRow(
            title: isDimmed ? "Brighten now" : "Dim now",
            value: overrideSummary(current, now: now),
            help: isDimmed
                ? "Show the dashboard at full brightness until the schedule next dims it."
                : "Dim the dashboard until the schedule next ends."
        ) {
            model.settings.nightDimOverride = NightDim.toggled(
                at: model.now(),
                schedule: schedule,
                current: current,
                calendar: model.calendar
            )
        }
        .accessibilityIdentifier("settings.night.dimNow")
    }

    private func overrideSummary(_ override: NightDimOverride, now: Date) -> String {
        switch override {
        case .dimmed(let until) where until > now: "Dimmed until \(untilLabel(until, now: now))"
        case .bright(let until) where until > now: "Bright until \(untilLabel(until, now: now))"
        default: "Follows schedule"
        }
    }

    private func untilLabel(_ date: Date, now: Date) -> String {
        let calendar = model.calendar
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let time = ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0).label
        if calendar.isDate(date, inSameDayAs: now) { return time }
        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        return "\(weekday) \(time)"
    }
}

private extension ClockTime {
    var label: String {
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(hour12):\(String(format: "%02d", minute)) \(hour < 12 ? "AM" : "PM")"
    }
}

/// Weather data attribution and app version (attribution arrives with WeatherKit in Phase 2).
enum AboutSettingsSection: SettingsSection {
    static let title = "About"
    static var isAvailable: Bool { false }

    static func rows(model: AppModel) -> some View {
        EmptyView()
    }
}
