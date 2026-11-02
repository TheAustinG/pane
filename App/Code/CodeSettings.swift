import SwiftUI

/// GitHub and Portainer connections (Phase 5).
enum CodeSettingsSection: SettingsSection {
    static let title = "Code"
    static var isAvailable: Bool { false }

    static func rows(model: AppModel) -> some View {
        EmptyView()
    }
}
