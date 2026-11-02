import SwiftUI

/// Night dim schedule and the manual Dim now toggle.
enum NightSettingsSection: SettingsSection {
    static let title = "Night"

    static func rows(model: AppModel) -> some View {
        EmptyView()
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
