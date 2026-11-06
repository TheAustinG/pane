import Foundation
import PaneCore

/// Launch arguments for repeatable states. UserDefaults reads `-key value` pairs, so a value that
/// starts with `-` is lost: `-home` cannot take a southern latitude.
struct LaunchOptions {
    var designPreview: String?
    /// A `WeatherScene` preset name, or nil for the live scene.
    var scene: String?
    /// Frozen app time: `2026-11-01T16:12` (local) or full ISO 8601 with an offset.
    var now: Date?
    /// `sample` fills the placeholder cards with the design preview's sample data.
    var fixtures: String?
    var quality: RenderQuality
    var showFPS: Bool
    var opensDebugMenu: Bool
    var opensSettings: Bool
    var resetsSettings: Bool
    /// `on` or `off` pins night dim regardless of the schedule.
    var nightDim: Bool?
    /// `-offline 1` makes every weather fetch fail like a dropped connection.
    var offline = false
    /// With `-fixtures sample`, seeds the offline cache with a report this many minutes old.
    var weatherAge: Int?
    /// `-storm storm|alert` starts with a simulated storm.
    var storm: StormSimulation?
    /// `-stormLayout side|bottom` sets the storm strip layout.
    var stormLayout: StormLayout?
    /// `-radar 1` opens radar as if the weather card was clicked.
    var opensRadar = false
    /// Debug builds: `-home 41.88,-87.63` sets and stores the home location, so later launches keep
    /// it until `-resetSettings 1`.
    var home: GeoPoint?
    /// `-homeScenes 1` opens the scene buttons as if the Home card was clicked.
    var opensHomeScenes = false
    /// Debug builds: `-homeNudge dryAir|humidAir|doorUnlockedLate|lightsOnAway|bedroomTVLate` lays
    /// states over the live ones that raise that nudge.
    var homeNudge: HomeNudgeKind?
    /// Debug builds: `-homeSetup prefill` fills the setup screen's fields from
    /// `local/Secrets.local.xcconfig` without saving them, so a UI test can finish setup.
    var homeSetupPrefill = false
    /// `-codeNudge on|off`: with `-fixtures sample`, picks the sample with or without the deploy
    /// nudge (on when absent); in Debug builds on live data, forces the nudge on or off.
    var codeNudge: Bool?
    /// Debug builds: `-codeSetup prefill` fills the GitHub and Portainer setup fields from
    /// `local/Secrets.local.xcconfig` without saving them, so a UI test can finish setup.
    var codeSetupPrefill = false
    /// `-background gradient|photo|auto` sets and stores the background setting.
    var background: BackgroundMode?
    /// Debug builds: `-photoCycle <seconds>` steps the photo through every slot at that interval and
    /// logs the memory footprint after each crossfade.
    var photoCycle: Double?

    static func parse(_ defaults: UserDefaults = .standard) -> LaunchOptions {
        LaunchOptions(
            designPreview: defaults.string(forKey: "designPreview"),
            scene: defaults.string(forKey: "scene"),
            now: defaults.string(forKey: "now").flatMap(parseDate),
            fixtures: defaults.string(forKey: "fixtures"),
            quality: RenderQuality.named(defaults.string(forKey: "quality")) ?? .standard,
            showFPS: defaults.bool(forKey: "fps"),
            opensDebugMenu: defaults.bool(forKey: "debugMenu"),
            opensSettings: defaults.bool(forKey: "settings"),
            resetsSettings: defaults.bool(forKey: "resetSettings"),
            nightDim: defaults.string(forKey: "nightDim").flatMap { ["on": true, "off": false][$0] },
            offline: defaults.bool(forKey: "offline"),
            weatherAge: defaults.object(forKey: "weatherAge") == nil ? nil : defaults.integer(forKey: "weatherAge"),
            storm: defaults.string(forKey: "storm").flatMap(StormSimulation.init(rawValue:)),
            stormLayout: defaults.string(forKey: "stormLayout").flatMap(StormLayout.init(rawValue:)),
            opensRadar: defaults.bool(forKey: "radar"),
            home: defaults.string(forKey: "home").flatMap(parsePoint),
            opensHomeScenes: defaults.bool(forKey: "homeScenes"),
            homeNudge: defaults.string(forKey: "homeNudge").flatMap(HomeNudgeKind.init(rawValue:)),
            homeSetupPrefill: defaults.string(forKey: "homeSetup") == "prefill",
            codeNudge: defaults.string(forKey: "codeNudge").flatMap { ["on": true, "off": false][$0] },
            codeSetupPrefill: defaults.string(forKey: "codeSetup") == "prefill",
            background: defaults.string(forKey: "background").flatMap(BackgroundMode.init(rawValue:)),
            photoCycle: defaults.object(forKey: "photoCycle") == nil ? nil : defaults.double(forKey: "photoCycle")
        )
    }

    static func parsePoint(_ text: String) -> GeoPoint? {
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, abs(parts[0]) <= 90, abs(parts[1]) <= 180 else { return nil }
        return GeoPoint(latitude: parts[0], longitude: parts[1])
    }

    static func parseDate(_ text: String) -> Date? {
        let full = ISO8601DateFormatter()
        if let date = full.date(from: text) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return date }
        }
        return nil
    }
}
