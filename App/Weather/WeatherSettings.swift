import SwiftUI

/// Location and attribution (Phase 2).
enum WeatherSettingsSection: SettingsSection {
    static let title = "Weather"
    static var isAvailable: Bool { false }

    static func rows(model: AppModel) -> some View {
        EmptyView()
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
