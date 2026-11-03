import Foundation
import PaneCore

/// Picks where Home Assistant data comes from: the sample fixtures for repeatable states,
/// otherwise the server saved on the setup screen.
enum HomeWiring {
    @MainActor
    static func controller(options: LaunchOptions, secrets: any SecretStore) -> HomeController {
        #if DEBUG
        if options.fixtures == "sample" {
            let controller = HomeController.preview(entities: HomeFixtures.entities, selection: HomeFixtures.selection)
            applyDebugOverrides(controller, options: options)
            return controller
        }
        #endif
        if options.resetsSettings { HomeController.reset(secrets: secrets) }
        let controller = HomeController(secrets: secrets, transport: URLSessionHATransportFactory())
        #if DEBUG
        applyDebugOverrides(controller, options: options)
        #endif
        return controller
    }

    #if DEBUG
    @MainActor
    private static func applyDebugOverrides(_ controller: HomeController, options: LaunchOptions) {
        guard let kind = options.homeNudge else { return }
        controller.debugOverrides = HomeFixtures.overrides(raising: kind, selection: controller.selection)
    }

    /// The server address and token from `local/Secrets.local.xcconfig`; empty on device and in
    /// Release builds.
    static var prefill: (address: String, token: String)? {
        let info = Bundle.main.infoDictionary
        guard let scheme = info?["PaneHAScheme"] as? String, !scheme.isEmpty,
              let host = info?["PaneHAHost"] as? String, !host.isEmpty,
              let token = info?["PaneHAToken"] as? String, !token.isEmpty else { return nil }
        return ("\(scheme)://\(host)", token)
    }
    #endif
}
