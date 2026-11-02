import PaneCore

/// Picks where weather comes from: fixtures and forced offline for repeatable states, otherwise
/// WeatherKit.
enum WeatherWiring {
    @MainActor
    static func controller(options: LaunchOptions) -> WeatherController {
        let controller = WeatherController(service: service(options: options))
        #if DEBUG
        if options.fixtures == "sample" { controller.location = AppModel.referenceLocation }
        #endif
        return controller
    }

    private static func service(options: LaunchOptions) -> any WeatherService {
        if options.offline { return OfflineWeatherService() }
        #if DEBUG
        if options.fixtures == "sample" {
            return WeatherFixtures.service(scene: options.scene, fixedNow: options.now)
        }
        #endif
        return OfflineWeatherService()
    }
}
