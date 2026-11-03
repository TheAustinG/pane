import PaneCore
import SwiftUI

/// Where the weather strip sits when radar takes over.
enum StormLayout: String, Codable, CaseIterable, Sendable {
    case side
    case bottom
}

/// Storm strip layout and automatic takeover.
enum StormSettingsSection: SettingsSection {
    static let title = "Storm mode"
    static var isAvailable: Bool { false }

    static func rows(model: AppModel) -> some View {
        EmptyView()
    }
}
