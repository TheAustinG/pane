import Foundation

/// When storm mode turns on and off: a warning-level alert, rain in the minute forecast, or a likely
/// shower in the hourly forecast. Once on, it holds until every rule has been clear for `hold`.
public struct StormRules: Hashable, Sendable {
    /// The precipitation chance at which the minute and hourly rules fire.
    public var enterChance: Double
    /// A minute or hourly rule that is already holding storm mode on keeps holding down to this
    /// chance, so a forecast swinging around `enterChance` between refreshes never flaps. Any other
    /// rule still needs `enterChance`.
    public var exitChance: Double
    /// Minutes at or over the chance, each with some intensity, before the minute rule fires.
    public var minuteCount: Int
    /// How far ahead the minute and hourly rules look.
    public var lookahead: TimeInterval
    /// How long every rule must stay clear before storm mode ends.
    public var hold: TimeInterval
    /// A report older than this says nothing: its alerts may have ended and its forecast moved on.
    /// Twice the weather card's stale mark, so a cached report cannot hold the takeover for long offline.
    public var staleAfter: TimeInterval
    /// `WeatherAlertInfo.severity` values that turn storm mode on. Advisories below them are still
    /// listed while storm mode is on for another reason.
    public var alertSeverities: Set<String>

    public init(
        enterChance: Double = 0.5,
        exitChance: Double = 0.3,
        minuteCount: Int = 3,
        lookahead: TimeInterval = 60 * 60,
        hold: TimeInterval = 20 * 60,
        staleAfter: TimeInterval = 60 * 60,
        alertSeverities: Set<String> = ["extreme", "severe"]
    ) {
        self.enterChance = enterChance
        self.exitChance = exitChance
        self.minuteCount = minuteCount
        self.lookahead = lookahead
        self.hold = hold
        self.staleAfter = staleAfter
        self.alertSeverities = alertSeverities
    }

    public func evaluate(report: WeatherReport?, at now: Date, previous: StormEvaluation = .calm) -> StormEvaluation {
        let holding = previous.state.isActive ? previous.state.reasons : []
        var reasons = Set<StormReason>()
        var alerts: [WeatherAlertInfo] = []
        if let report, isUsable(report, at: now) {
            alerts = currentAlerts(in: report, at: now)
            if alerts.contains(where: triggers) { reasons.insert(.alert) }
            let minuteThreshold = holding.contains(.minutePrecipitation) ? exitChance : enterChance
            if minuteRuleHolds(report.minutes ?? [], at: now, threshold: minuteThreshold) { reasons.insert(.minutePrecipitation) }
            let hourlyThreshold = holding.contains(.hourlyChance) ? exitChance : enterChance
            if hourlyRuleHolds(report.hourly, at: now, threshold: hourlyThreshold) { reasons.insert(.hourlyChance) }
        }
        if !reasons.isEmpty {
            return StormEvaluation(state: StormState(isActive: true, reasons: reasons, alerts: alerts), lastSignal: now)
        }
        guard previous.state.isActive, let lastSignal = previous.lastSignal else { return .calm }
        // A signal stamped after `now` means the clock went back; holding from it could last for hours.
        let heldSince = min(lastSignal, now)
        guard now.timeIntervalSince(heldSince) < hold else { return .calm }
        return StormEvaluation(
            state: StormState(isActive: true, reasons: previous.state.reasons, alerts: alerts),
            lastSignal: heldSince
        )
    }

    /// Whether the alert alone turns storm mode on.
    public func triggers(_ alert: WeatherAlertInfo) -> Bool {
        alertSeverities.contains(alert.severity)
    }

    /// Alerts of a usable report that have not ended, most severe first, exactly as issued. An alert
    /// that ended between refreshes must not hold the takeover.
    public func currentAlerts(in report: WeatherReport?, at now: Date) -> [WeatherAlertInfo] {
        guard let report, isUsable(report, at: now) else { return [] }
        return Self.mostSevereFirst((report.alerts ?? []).filter { !$0.hasEnded(at: now) })
    }

    func isUsable(_ report: WeatherReport, at now: Date) -> Bool {
        now.timeIntervalSince(report.fetchedAt) <= staleAfter
    }

    /// Minutes already over are ignored.
    func minuteRuleHolds(_ minutes: [MinuteForecast], at now: Date, threshold: Double) -> Bool {
        let end = now.addingTimeInterval(lookahead)
        let wet = minutes.filter { minute in
            minute.date.addingTimeInterval(60) > now && minute.date < end
                && minute.precipitationChance >= threshold && minute.precipitationIntensity > 0
        }
        return wet.count >= minuteCount
    }

    /// The hour under way, or one starting within `lookahead`.
    func hourlyRuleHolds(_ hours: [HourForecast], at now: Date, threshold: Double) -> Bool {
        let end = now.addingTimeInterval(lookahead)
        return hours.contains { hour in
            hour.date.addingTimeInterval(3600) > now && hour.date <= end && hour.precipitationChance >= threshold
        }
    }

    static let severityOrder = ["extreme", "severe", "moderate", "minor"]

    /// Unknown severities sort last; equal severities keep WeatherKit's order.
    static func mostSevereFirst(_ alerts: [WeatherAlertInfo]) -> [WeatherAlertInfo] {
        func rank(_ alert: WeatherAlertInfo) -> Int {
            severityOrder.firstIndex(of: alert.severity) ?? severityOrder.count
        }
        return alerts.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }
}

/// What the rules decided, fed back in as `previous` so storm mode holds through brief gaps.
public struct StormEvaluation: Hashable, Sendable {
    public var state: StormState
    /// The last time any rule held.
    public var lastSignal: Date?

    public init(state: StormState, lastSignal: Date?) {
        self.state = state
        self.lastSignal = lastSignal
    }

    public static let calm = StormEvaluation(state: .calm, lastSignal: nil)
}
