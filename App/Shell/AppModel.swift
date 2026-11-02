import Foundation
import Observation
import PaneCore

struct AppClock: Hashable, Sendable {
    /// Frozen time from `-now`; nil follows the real clock.
    var fixed: Date?
    /// Debug time scrub, added to whichever clock is in use.
    var offset: TimeInterval = 0

    func now(_ real: Date = .now) -> Date {
        (fixed ?? real).addingTimeInterval(offset)
    }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var nightSchedule: NightSchedule {
        didSet { store(nightSchedule, key: Keys.nightSchedule) }
    }

    var nightDimOverride: NightDimOverride {
        didSet { store(nightDimOverride, key: Keys.nightDimOverride) }
    }

    init(defaults: UserDefaults = .standard, reset: Bool = false) {
        self.defaults = defaults
        if reset {
            [Keys.nightSchedule, Keys.nightDimOverride].forEach { defaults.removeObject(forKey: $0) }
        }
        nightSchedule = Self.load(NightSchedule.self, from: defaults, key: Keys.nightSchedule) ?? .standard
        nightDimOverride = Self.load(NightDimOverride.self, from: defaults, key: Keys.nightDimOverride) ?? .none
    }

    private enum Keys {
        static let nightSchedule = "settings.nightSchedule"
        static let nightDimOverride = "settings.nightDimOverride"
    }

    private func store<T: Encodable>(_ value: T, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

/// App-wide state shared by the dashboard, background, settings and debug menu.
@MainActor
@Observable
final class AppModel {
    var clock: AppClock
    /// A reference location until Settings stores the home location (Phase 2).
    var location = GeoPoint(latitude: 41.88, longitude: -87.63)
    /// Set by `-scene` or the debug menu; wins over the live scene.
    var sceneOverride: WeatherScene?
    /// Live weather replaces this in Phase 2.
    var liveCondition: ConditionFamily = .clear
    var quality: RenderQuality
    var showFPS: Bool
    var isDebugMenuPresented: Bool
    var isSettingsPresented: Bool
    let usesSampleFixtures: Bool
    let pinnedNightDim: Bool?
    let settings: AppSettings
    let secrets: any SecretStore
    @ObservationIgnored var calendar = Calendar.current

    init(options: LaunchOptions, settings: AppSettings, secrets: any SecretStore) {
        clock = AppClock(fixed: options.now)
        sceneOverride = options.scene.flatMap(WeatherScene.preset(named:))
        quality = options.quality
        showFPS = options.showFPS
        isDebugMenuPresented = options.opensDebugMenu
        isSettingsPresented = options.opensSettings
        usesSampleFixtures = options.fixtures == "sample"
        pinnedNightDim = options.nightDim
        self.settings = settings
        self.secrets = secrets
    }

    func now(_ real: Date = .now) -> Date {
        clock.now(real)
    }

    func scene(at date: Date) -> WeatherScene {
        sceneOverride ?? SceneEngine.scene(condition: liveCondition, at: date, location: location)
    }

    func palette(at date: Date) -> ScenePalette {
        SceneEngine.palette(for: scene(at: date))
    }

    func isNightDimmed(at date: Date) -> Bool {
        pinnedNightDim ?? NightDim.isDimmed(
            at: date,
            schedule: settings.nightSchedule,
            override: settings.nightDimOverride,
            calendar: calendar
        )
    }
}
