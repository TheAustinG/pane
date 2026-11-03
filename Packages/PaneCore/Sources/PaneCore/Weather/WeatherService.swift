import Foundation

/// Where weather comes from. The live app uses `WeatherKitService`; tests, fixtures and the forced
/// offline mode swap in their own.
public protocol WeatherService: Sendable {
    func report(for location: GeoPoint) async throws -> WeatherReport
    func attribution() async throws -> WeatherAttributionInfo
    /// Billable WeatherKit calls that one `report(for:)` costs, for the monthly budget.
    var callsPerReport: Int { get }
}

/// How fresh the shown data is, for the "Updated 20 min ago" note.
public enum Freshness: Hashable, Sendable {
    case none
    case fresh
    /// The last refresh failed; the shown data is this many minutes old.
    case delayed(minutes: Int)
    /// Older than the stale threshold, whether or not the last refresh failed.
    case stale(minutes: Int)

    public var label: String? {
        switch self {
        case .none, .fresh: nil
        case .delayed(let minutes), .stale(let minutes): Self.updatedLabel(minutes: minutes)
        }
    }

    static func updatedLabel(minutes: Int) -> String {
        switch minutes {
        case ..<1: "Updated just now"
        case ..<60: "Updated \(minutes) min ago"
        case ..<(24 * 60): "Updated \(minutes / 60) h ago"
        default: "Updated \(minutes / (24 * 60)) d ago"
        }
    }
}

/// Fails every call the way a dropped connection does, for `-offline 1`.
public struct OfflineWeatherService: WeatherService {
    public init() {}

    public var callsPerReport: Int { 0 }

    public func report(for location: GeoPoint) async throws -> WeatherReport {
        throw URLError(.notConnectedToInternet)
    }

    public func attribution() async throws -> WeatherAttributionInfo {
        throw URLError(.notConnectedToInternet)
    }
}
