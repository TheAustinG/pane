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
    /// Debug override; nil follows the weather report. Setting it updates `state` at once.
    public var simulation: StormSimulation? {
        didSet {
            if simulation != nil { isDismissed = false }
            evaluate()
        }
    }
    public private(set) var isDismissed = false

    /// The longest the loop waits between evaluations when the report does not change.
    public static let tick: TimeInterval = 60

    @ObservationIgnored private let weather: WeatherController
    @ObservationIgnored private let clock: any WeatherClock
    @ObservationIgnored private let rules: StormRules
    @ObservationIgnored private var evaluation = StormEvaluation.calm
    @ObservationIgnored private var dismissedAlertIDs: Set<String> = []

    public init(
        weather: WeatherController,
        clock: any WeatherClock = SystemWeatherClock(),
        simulation: StormSimulation? = nil,
        rules: StormRules = StormRules()
    ) {
        self.weather = weather
        self.clock = clock
        self.rules = rules
        self.simulation = simulation
        evaluate()
    }

    public var isTakeoverActive: Bool {
        state.isActive && !isDismissed
    }

    /// Hides the takeover until storm mode ends or an alert with a new id arrives. Clears a simulation.
    public func dismiss() {
        if simulation != nil {
            simulation = nil
        } else if state.isActive {
            dismissedAlertIDs = Set(state.alerts.map(\.id))
            isDismissed = true
        }
    }

    /// Re-evaluates whenever the report changes and at least every `tick`, until the calling task
    /// is cancelled.
    public func run() async {
        while !Task.isCancelled {
            evaluate()
            await waitForReport(until: clock.now.addingTimeInterval(Self.tick))
        }
    }

    /// Measured on the controller's clock: a pinned or scrubbed app clock says nothing about the storm.
    func evaluate() {
        evaluation = rules.evaluate(report: weather.report, at: clock.now, previous: evaluation)
        let next = simulation.map(Self.simulatedState) ?? evaluation.state
        if next != state { state = next }
        if isDismissed, !next.isActive || next.alerts.contains(where: { !dismissedAlertIDs.contains($0.id) }) {
            isDismissed = false
        }
    }

    private func waitForReport(until deadline: Date) async {
        let clock = clock
        let sleeper = Task { try await clock.sleep(until: deadline) }
        withObservationTracking {
            _ = weather.report
        } onChange: {
            sleeper.cancel()
        }
        await withTaskCancellationHandler {
            _ = try? await sleeper.value
        } onCancel: {
            sleeper.cancel()
        }
    }

    private static func simulatedState(_ simulation: StormSimulation) -> StormState {
        switch simulation {
        case .storm: StormState(isActive: true, reasons: [.minutePrecipitation], alerts: [])
        case .alert: StormState(isActive: true, reasons: [.alert], alerts: [sampleAlert])
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
