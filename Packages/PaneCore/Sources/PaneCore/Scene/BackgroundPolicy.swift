import Foundation

public enum BackgroundMode: String, CaseIterable, Hashable, Sendable, Codable {
    case gradient
    case photo
    /// A photo in daylight; the gradient at night and while storm mode is on.
    case auto
}

public enum BackgroundKind: String, Hashable, Sendable {
    case gradient
    case photo
}

/// The four lights a photo is chosen for.
public enum TimeOfDay: String, CaseIterable, Hashable, Sendable, Codable {
    case dawn
    case day
    case dusk
    case night
}

/// One photo slot: a condition family at a time of day. `name` is the asset file stem.
public struct PhotoKey: Hashable, Sendable, Codable {
    public var condition: ConditionFamily
    public var time: TimeOfDay

    public init(condition: ConditionFamily, time: TimeOfDay) {
        self.condition = condition
        self.time = time
    }

    public var name: String { "\(condition.rawValue)-\(time.rawValue)" }

    public init?(name: String) {
        let parts = name.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let condition = ConditionFamily(rawValue: parts[0]),
              let time = TimeOfDay(rawValue: parts[1]) else { return nil }
        self.init(condition: condition, time: time)
    }

    /// Every slot, condition-major in `ConditionFamily` order, then `TimeOfDay` order.
    public static let all: [PhotoKey] = ConditionFamily.allCases.flatMap { condition in
        TimeOfDay.allCases.map { PhotoKey(condition: condition, time: $0) }
    }
}

public enum BackgroundPolicy {
    /// The sun altitude, in degrees, below which it is night for photo choice.
    public static let nightBelow = -6.0
    /// The sun altitude, in degrees, at or above which it is day for photo choice.
    public static let dayFrom = 8.0
    /// Auto shows the gradient once the sun is below this altitude.
    public static let autoPhotoFrom = 0.0

    public static func kind(mode: BackgroundMode, scene: WeatherScene, isStormActive: Bool) -> BackgroundKind {
        switch mode {
        case .gradient: .gradient
        case .photo: .photo
        case .auto: scene.sunAltitude >= autoPhotoFrom && !isStormActive ? .photo : .gradient
        }
    }

    public static func timeOfDay(for scene: WeatherScene) -> TimeOfDay {
        if scene.sunAltitude < nightBelow { return .night }
        if scene.sunAltitude >= dayFrom { return .day }
        return scene.isMorning ? .dawn : .dusk
    }

    public static func photoKey(for scene: WeatherScene) -> PhotoKey {
        PhotoKey(condition: scene.condition, time: timeOfDay(for: scene))
    }
}
