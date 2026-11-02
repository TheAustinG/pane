import SwiftUI

/// Settings: the registry's sections as a native list, with a help pane for the focused row.
struct SettingsRoot: View {
    let model: AppModel

    var body: some View {
        List {
            ForEach(Array(SettingsRegistry.availableSections().enumerated()), id: \.offset) { _, section in
                Section(section.title) {
                    SettingsRegistry.rows(for: section, model: model)
                }
            }
        }
    }
}
