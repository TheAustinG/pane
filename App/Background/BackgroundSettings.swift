import SwiftUI

/// Gradient, Photo or Auto (Phase 6).
enum BackgroundSettingsSection: SettingsSection {
    static let title = "Background"
    static var isAvailable: Bool { false }

    static func rows(model: AppModel) -> some View {
        EmptyView()
    }
}
