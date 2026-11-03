import Foundation
import Observation

/// Why storm mode is on.
public enum StormReason: String, Hashable, Sendable, CaseIterable {
    case alert
    case minutePrecipitation
    case hourlyChance
}

/// What the takeover shows. `alerts` are exactly as issued, most severe first.
public struct StormState: Hashable, Sendable {
    public var isActive: Bool
    public var reasons: Set<StormReason>
    public var alerts: [WeatherAlertInfo]

    public init(isActive: Bool, reasons: Set<StormReason>, alerts: [WeatherAlertInfo]) {
        self.isActive = isActive
        self.reasons = reasons
        self.alerts = alerts
    }

    public static let calm = StormState(isActive: false, reasons: [], alerts: [])
}

/// Debug "simulate storm": forces storm mode, with or without the sample alert.
public enum StormSimulation: String, Hashable, Sendable, CaseIterable {
    case storm
    case alert
}

/// Decides when radar takes over the dashboard. The app reads `isTakeoverActive` (and its own
/// automatic takeover setting); Back during a takeover calls `dismiss()`.
@MainActor
@Observable
public final class StormController {
    public private(set) var state: StormState = .calm
    /// Debug override; nil follows the weather report.
    public var simulation: StormSimulation? {
        didSet { evaluate() }
    }
    public private(set) var isDismissed = false

    @ObservationIgnored private let weather: WeatherController
    @ObservationIgnored private let clock: any WeatherClock

    public init(weather: WeatherController, clock: any WeatherClock = SystemWeatherClock(), simulation: StormSimulation? = nil) {
        self.weather = weather
        self.clock = clock
        self.simulation = simulation
        evaluate()
    }

    public var isTakeoverActive: Bool {
        state.isActive && !isDismissed
    }

    /// Hides the takeover until storm mode ends or a new alert arrives. Clears a simulation.
    public func dismiss() {
        if simulation != nil {
            simulation = nil
        } else {
            isDismissed = true
        }
    }

    /// Keeps `state` current until the calling task is cancelled.
    public func run() async {
        evaluate()
    }

    private func evaluate() {
        switch simulation {
        case .storm: state = StormState(isActive: true, reasons: [.minutePrecipitation], alerts: [])
        case .alert: state = StormState(isActive: true, reasons: [.alert], alerts: [Self.sampleAlert])
        case nil: state = .calm
        }
    }

    /// Stand-in for a real alert in simulations and fixtures; it links to Apple's alert page.
    public static let sampleAlert = WeatherAlertInfo(
        id: "sample",
        summary: "Severe Thunderstorm Warning",
        source: "National Weather Service",
        severity: "severe",
        detailsURL: URL(string: "https://weatherkit.apple.com/alertDetails/index.html")!,
        region: nil
    )
}
