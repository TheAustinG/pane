import SwiftUI

/// Home Assistant connection, entities and nudges (Phase 4).
enum HomeSettingsSection: SettingsSection {
    static let title = "Home"
    static var isAvailable: Bool { false }

    static func rows(model: AppModel) -> some View {
        EmptyView()
    }
}
