import Foundation
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

    /// Debug simulator builds start with the home location from `local/Secrets.local.xcconfig`, so
    /// live runs need no city search. Device and Release builds leave the keys empty.
    @MainActor
    static func prefillHomeLocation(_ settings: AppSettings, options: LaunchOptions) {
        #if DEBUG
        guard settings.homeLocation == nil, !options.resetsSettings,
              let latitude = plistDouble("PaneHomeLatitude"),
              let longitude = plistDouble("PaneHomeLongitude") else { return }
        settings.homeLocation = HomeLocation(name: "Home", coordinate: GeoPoint(latitude: latitude, longitude: longitude))
        #endif
    }

    private static func plistDouble(_ key: String) -> Double? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap(Double.init)
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
