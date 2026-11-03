import Foundation
import Observation

/// Why storm mode is on.
public enum StormReason: String, Hashable, Sendable, CaseIterable {
    case alert
    case minutePrecipitation
    case hourlyChance
}

/// What the takeover shows. `alerts` are every alert in the report while storm mode is on,
/// including advisories too mild to turn it on, exactly as issued and most severe first.
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
    /// Debug override; nil follows the weather report. Setting it updates `state` at once, and a
    /// simulation shows whatever was dismissed.
    public var simulation: StormSimulation? {
        didSet { evaluate() }
    }
    /// Whether Back hid the real storm's takeover. It lasts until storm mode next goes calm; until
    /// then only a warning with a new id shows the takeover again.
    public private(set) var isDismissed = false
    /// Alerts to show with radar: `state.alerts` while storm mode or a simulation is on, otherwise
    /// every current alert, so radar opened from the weather card lists advisories too mild for
    /// storm mode. Most severe first, exactly as issued.
    public private(set) var alerts: [WeatherAlertInfo] = []

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
        state.isActive && (simulation != nil || !isDismissed)
    }

    /// Hides the takeover until storm mode next goes calm, and dismisses every alert on it. Clears a
    /// simulation instead.
    public func dismiss() {
        if simulation != nil {
            simulation = nil
        } else if state.isActive {
            dismissedAlertIDs.formUnion(state.alerts.map(\.id))
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
        let now = clock.now
        evaluation = rules.evaluate(report: weather.report, at: now, previous: evaluation)
        let next = simulation.map(Self.simulatedState) ?? evaluation.state
        if next != state { state = next }
        let shown = next.isActive ? next.alerts : rules.currentAlerts(in: weather.report, at: now)
        if shown != alerts { alerts = shown }
        updateDismissal(for: evaluation.state)
    }

    private func updateDismissal(for storm: StormState) {
        if !storm.isActive {
            dismissedAlertIDs = []
            if isDismissed { isDismissed = false }
        } else if isDismissed, storm.alerts.contains(where: { rules.triggers($0) && !dismissedAlertIDs.contains($0.id) }) {
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
