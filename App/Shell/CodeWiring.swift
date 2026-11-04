import Foundation
import PaneCore

/// Picks where Code card data comes from: the sample fixtures for repeatable states, otherwise the
/// GitHub token and Portainer server saved on the setup screens.
enum CodeWiring {
    @MainActor
    static func controller(options: LaunchOptions, secrets: any SecretStore) -> CodeController {
        #if DEBUG
        if options.fixtures == "sample" {
            let controller = CodeFixtures.controller(behind: options.codeNudge ?? true)
            return controller
        }
        #endif
        if options.resetsSettings { CodeController.reset(secrets: secrets) }
        let controller = CodeController(
            secrets: secrets,
            http: URLSessionHTTPClient(),
            portainerHTTP: { PortainerHTTPClient(server: $0) }
        )
        #if DEBUG
        if let nudge = options.codeNudge { controller.debugNudge = nudge }
        #endif
        return controller
    }

    #if DEBUG
    /// The GitHub token from `local/Secrets.local.xcconfig`; empty on device and in Release builds.
    static var githubPrefill: String? {
        nonEmpty(Bundle.main.infoDictionary?["PaneGitHubToken"])
    }

    /// The Portainer address, environment id and token from `local/Secrets.local.xcconfig`; empty on
    /// device and in Release builds.
    static var portainerPrefill: (address: String, environmentID: String, token: String)? {
        let info = Bundle.main.infoDictionary
        guard let scheme = nonEmpty(info?["PanePortainerScheme"]),
              let host = nonEmpty(info?["PanePortainerHost"]),
              let environment = nonEmpty(info?["PanePortainerEnvironment"]),
              let token = nonEmpty(info?["PanePortainerToken"]) else { return nil }
        return ("\(scheme)://\(host)", environment, token)
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
    #endif
}
