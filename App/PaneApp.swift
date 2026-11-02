import PaneCore
import SwiftUI

@main
struct PaneApp: App {
    @State private var model: AppModel
    private let options: LaunchOptions

    init() {
        let options = LaunchOptions.parse()
        self.options = options
        let settings = AppSettings(reset: options.resetsSettings)
        WeatherWiring.prefillHomeLocation(settings, options: options)
        _model = State(initialValue: AppModel(
            options: options,
            settings: settings,
            secrets: KeychainSecretStore(service: Bundle.main.bundleIdentifier ?? "pane"),
            weather: WeatherWiring.controller(options: options)
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, options: options)
                .preferredColorScheme(.dark)
                .task { await model.weather.run() }
        }
    }
}

private struct RootView: View {
    let model: AppModel
    let options: LaunchOptions

    var body: some View {
        #if DEBUG
        if let page = PreviewPage(rawValue: options.designPreview ?? "") {
            DesignPreviewView(page: page)
        } else {
            DashboardView(model: model)
        }
        #else
        DashboardView(model: model)
        #endif
    }
}
