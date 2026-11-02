import PaneCore
import SwiftUI

/// Location and attribution (Phase 2).
enum WeatherSettingsSection: SettingsSection {
    static let title = "Weather"
    static var isAvailable: Bool { true }

    static func rows(model: AppModel) -> some View {
        WeatherSettingsRows(model: model)
    }

    static let locationHelp = "Pane has no GPS. Search for your city once; it is stored as coordinates."
}

private struct WeatherSettingsRows: View {
    let model: AppModel

    var body: some View {
        NavigationLink {
            LocationSearchScreen(model: model)
        } label: {
            LabeledContent("Location", value: model.settings.homeLocation?.name ?? "Not set")
        }
        .settingsHelp(WeatherSettingsSection.locationHelp)
        .accessibilityIdentifier("settings.weather.location")
    }
}

/// Storm strip layout and storm mode options (Phase 3).
enum StormSettingsSection: SettingsSection {
    static let title = "Storm mode"
    static var isAvailable: Bool { false }

    static func rows(model: AppModel) -> some View {
        EmptyView()
    }
}
