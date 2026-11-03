import PaneCore
import SwiftUI

/// Home Assistant connection and entities.
enum HomeSettingsSection: SettingsSection {
    static let title = "Home"

    static func rows(model: AppModel) -> some View {
        HomeSettingsRows(model: model)
    }

    static let serverHelp = "Server address and access token for a Home Assistant user without admin rights."
    static let goodnightHelp = "The scene button that also dims the dashboard. Auto uses the scene named Goodnight."

    static func nudgeHelp(_ kind: HomeNudgeKind) -> String {
        switch kind {
        case .dryAir: "Shows a nudge on the Home card when indoor humidity drops below 35 percent."
        case .humidAir: "Shows a nudge on the Home card when indoor humidity rises above 60 percent."
        case .doorUnlockedLate: "Shows a nudge when the door lock is unlocked after 10 PM."
        case .lightsOnAway: "Shows a nudge when a light is on and everyone is away."
        case .bedroomTVLate: "Shows a nudge when the bedroom TV is on after midnight."
        }
    }
}

/// One toggle per Home card nudge.
enum HomeNudgeSettingsSection: SettingsSection {
    static let title = "Nudges"

    static func rows(model: AppModel) -> some View {
        ForEach(HomeNudgeKind.allCases, id: \.self) { kind in
            Toggle(kind.settingsTitle, isOn: Binding(
                get: { model.home.nudgePreferences.isEnabled(kind) },
                set: { model.home.nudgePreferences.setEnabled($0, kind) }
            ))
            .settingsHelp(HomeSettingsSection.nudgeHelp(kind))
            .accessibilityIdentifier("settings.home.nudge.\(kind.rawValue)")
        }
    }
}

private struct HomeSettingsRows: View {
    let model: AppModel

    var body: some View {
        let home = model.home
        NavigationLink {
            HomeSetupScreen(model: model)
        } label: {
            LabeledContent("Home Assistant", value: home.connection.settingsValue)
        }
        .settingsHelp(HomeSettingsSection.serverHelp)
        .accessibilityIdentifier("settings.home.server")

        ForEach(HomeEntityRole.allCases, id: \.self) { role in
            roleRow(role)
        }

        SettingsChoiceRow(
            title: "Starts night dim",
            help: HomeSettingsSection.goodnightHelp,
            options: [String?.none] + home.selection.scenes.map { Optional($0) },
            selection: Binding(
                get: { model.home.selection.goodnightScene },
                set: { model.home.selection.goodnightScene = $0 }
            ),
            label: { id in id.map { model.home.entities[$0]?.friendlyName ?? $0 } ?? "Auto (Goodnight)" }
        )
        .accessibilityIdentifier("settings.home.goodnight")
    }

    @ViewBuilder
    private func roleRow(_ role: HomeEntityRole) -> some View {
        let home = model.home
        let names = home.selection.entityIDs(for: role).map { home.entities[$0]?.friendlyName ?? $0 }
        let value = names.isEmpty ? "None" : names.joined(separator: ", ")
        if home.entities.isEmpty {
            // Stays focusable so the help pane can say why it does nothing.
            SettingsValueRow(title: role.title, value: value, help: role.disconnectedHelp) {}
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.home.role.\(role.rawValue)")
        } else {
            NavigationLink {
                HomeEntityPicker(model: model, role: role)
            } label: {
                LabeledContent(role.title) { Text(value).lineLimit(1) }
            }
            .settingsHelp(role.help)
            .accessibilityIdentifier("settings.home.role.\(role.rawValue)")
        }
    }
}
