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

    var hasPrecipitation: Bool {
        reasons.contains(.minutePrecipitation) || reasons.contains(.hourlyChance)
    }
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
    /// Whether a dismissal hides the real storm's takeover. Dismissed alert ids stay dismissed
    /// through calm spells, so only a warning with a new id, or rain after storm mode has gone calm
    /// and come back, shows the takeover again.
    public private(set) var isDismissed = false

    /// The longest the loop waits between evaluations when the report does not change.
    public static let tick: TimeInterval = 60
    /// A dismissed alert id is forgotten once no report has carried it for this long.
    public static let dismissalMemory: TimeInterval = 24 * 3600

    @ObservationIgnored private let weather: WeatherController
    @ObservationIgnored private let clock: any WeatherClock
    @ObservationIgnored private let rules: StormRules
    @ObservationIgnored private var evaluation = StormEvaluation.calm
    /// When each dismissed alert id was last seen in a report.
    @ObservationIgnored private var dismissedAlerts: [String: Date] = [:]
    /// Back was pressed during the current storm, so rain joining it does not show it again.
    @ObservationIgnored private var dismissedThisStorm = false

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

    /// Hides the takeover and dismisses every alert on it. Clears a simulation instead.
    public func dismiss() {
        if simulation != nil {
            simulation = nil
        } else if state.isActive {
            let now = clock.now
            for alert in state.alerts { dismissedAlerts[alert.id] = now }
            dismissedThisStorm = true
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
        let wasActive = evaluation.state.isActive
        evaluation = rules.evaluate(report: weather.report, at: now, previous: evaluation)
        let next = simulation.map(Self.simulatedState) ?? evaluation.state
        if next != state { state = next }
        rememberDismissedAlerts(at: now)
        let hidden = resolveDismissal(for: evaluation.state, wasActive: wasActive)
        if hidden != isDismissed { isDismissed = hidden }
    }

    /// Returns whether the takeover stays hidden, and forgets a dismissal of this storm once it ends.
    private func resolveDismissal(for storm: StormState, wasActive: Bool) -> Bool {
        guard storm.isActive else {
            dismissedThisStorm = false
            return false
        }
        if storm.alerts.contains(where: { rules.triggers($0) && dismissedAlerts[$0.id] == nil }) {
            dismissedThisStorm = false
            return false
        }
        // A storm with no warning left undismissed starts hidden unless it brings rain.
        if !wasActive { return !storm.hasPrecipitation }
        if isDismissed, !dismissedThisStorm, storm.hasPrecipitation { return false }
        return isDismissed
    }

    private func rememberDismissedAlerts(at now: Date) {
        for alert in weather.report?.alerts ?? [] {
            if let seen = dismissedAlerts[alert.id], seen < now { dismissedAlerts[alert.id] = now }
        }
        dismissedAlerts = dismissedAlerts.filter { now.timeIntervalSince($0.value) < Self.dismissalMemory }
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
