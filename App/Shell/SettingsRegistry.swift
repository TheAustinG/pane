import SwiftUI

/// One section of the Settings list. Each section lives in its feature's folder and is listed in
/// `SettingsRegistry` from Phase 1 on, so later phases fill in their own file and never edit this
/// one. A section that has nothing to show yet returns `isAvailable == false` and is skipped.
@MainActor
protocol SettingsSection {
    associatedtype Rows: View
    static var title: String { get }
    static var isAvailable: Bool { get }
    @ViewBuilder static func rows(model: AppModel) -> Rows
}

extension SettingsSection {
    static var isAvailable: Bool { true }
}

enum SettingsRegistry {
    /// Display order of the Settings list.
    @MainActor static let sections: [any SettingsSection.Type] = [
        WeatherSettingsSection.self,
        StormSettingsSection.self,
        BackgroundSettingsSection.self,
        NightSettingsSection.self,
        HomeSettingsSection.self,
        HomeNudgeSettingsSection.self,
        CodeSettingsSection.self,
        AboutSettingsSection.self,
    ]

    @MainActor
    static func availableSections() -> [any SettingsSection.Type] {
        sections.filter { $0.isAvailable }
    }

    @MainActor
    static func rows(for section: any SettingsSection.Type, model: AppModel) -> AnyView {
        AnyView(section.rows(model: model))
    }
}
