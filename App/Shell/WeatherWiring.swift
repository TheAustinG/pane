import Foundation
import PaneCore

/// Picks where weather comes from: fixtures and forced offline for repeatable states, otherwise
/// WeatherKit.
enum WeatherWiring {
    @MainActor
    static func controller(options: LaunchOptions) -> WeatherController {
        #if DEBUG
        if options.fixtures == "sample" { return fixtureController(options: options) }
        #endif
        if options.resetsSettings {
            try? FileManager.default.removeItem(at: WeatherCache.defaultDirectory)
        }
        let service: any WeatherService = options.offline ? OfflineWeatherService() : WeatherKitService()
        return WeatherController(service: service)
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

    #if DEBUG
    /// Fixture runs keep their reports and call counts in memory, away from the live cache and budget.
    /// `-weatherAge` seeds the cache with a sample that old, as if fetched before going offline.
    @MainActor
    private static func fixtureController(options: LaunchOptions) -> WeatherController {
        let cache = WeatherCache.inMemory()
        if let minutes = options.weatherAge {
            let fetchedAt = (options.now ?? .now).addingTimeInterval(-Double(minutes) * 60)
            cache.save(WeatherFixtures.report(scene: options.scene, at: fetchedAt))
        }
        let service: any WeatherService = options.offline
            ? OfflineWeatherService()
            : WeatherFixtures.service(scene: options.scene, fixedNow: options.now)
        let controller = WeatherController(
            service: service,
            cache: cache,
            budget: CallBudget(store: InMemoryKeyValueStore())
        )
        controller.location = AppModel.referenceLocation
        return controller
    }
    #endif
}
