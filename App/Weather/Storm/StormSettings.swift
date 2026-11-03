import PaneCore
import SwiftUI

/// Where the weather strip sits when radar takes over.
enum StormLayout: String, Codable, CaseIterable, Sendable {
    case side
    case bottom

    var title: String {
        switch self {
        case .side: "Side"
        case .bottom: "Bottom"
        }
    }
}

/// Storm strip layout and automatic takeover.
enum StormSettingsSection: SettingsSection {
    static let title = "Storm mode"

    static func rows(model: AppModel) -> some View {
        StormSettingsRows(model: model)
    }
}

private struct StormSettingsRows: View {
    let model: AppModel

    var body: some View {
        let settings = Bindable(model.settings)
        SettingsChoiceRow(
            title: "Storm strip",
            help: "Where the weather strip sits when radar takes over: a column at the side, or a strip along the bottom.",
            options: StormLayout.allCases,
            selection: settings.stormLayout,
            label: \.title
        )
        .accessibilityIdentifier("settings.storm.layout")
        Toggle("Automatic takeover", isOn: settings.stormAutomatic)
            .settingsHelp("Radar takes over when a weather alert is issued for your location or rain is due within the hour. Off: radar opens only from the weather card.")
            .accessibilityIdentifier("settings.storm.automatic")
    }
}
