import Foundation

/// Launch arguments for repeatable states. UserDefaults reads `-key value` pairs, so a value that
/// starts with `-` is lost; none of these take negative numbers.
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
            nightDim: defaults.string(forKey: "nightDim").flatMap { ["on": true, "off": false][$0] }
        )
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
