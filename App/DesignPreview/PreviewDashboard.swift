#if DEBUG
import PaneCore
import SwiftUI

/// Builds the app model the design preview's dashboard pages run the real `DashboardView` on.
@MainActor
enum PreviewDashboard {
    static func model(scene: ScenePreset, night: Bool) -> AppModel {
        let defaults = UserDefaults(suiteName: "pane.designPreview")!
        let options = LaunchOptions(
            designPreview: nil,
            scene: scene.id,
            now: scene.sampleDate,
            fixtures: "sample",
            quality: .standard,
            showFPS: false,
            opensDebugMenu: false,
            opensSettings: false,
            resetsSettings: true
        )
        let settings = AppSettings(defaults: defaults, reset: true)
        if night {
            settings.nightDimOverride = .dimmed(until: .distantFuture)
        } else {
            settings.nightSchedule.isEnabled = false
        }
        return AppModel(options: options, settings: settings, secrets: InMemorySecretStore())
    }

    /// `-previewFocus` ids from the earlier sample layout, plus the Settings button.
    static func focus(for id: String?) -> DashboardFocus? {
        switch id {
        case "weather": .card(.current)
        case "forecast": .card(.forecast)
        case "home": .card(.home)
        case "github": .card(.code)
        case "settings": .settings
        default: nil
        }
    }
}
#endif
