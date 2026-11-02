import Foundation

/// When the storm sky flashes: at random 20 to 60 second intervals, never twice within 20 s,
/// even if the storm layer restarts.
public struct LightningSchedule: Sendable {
    public static let minimumInterval: TimeInterval = 20
    public static let maximumInterval: TimeInterval = 60
    /// White opacity at the flash's peak.
    public static let flashOpacity = 0.10
    public static let flashDuration: TimeInterval = 0.15

    public private(set) var lastFlash: Date?

    public init(lastFlash: Date? = nil) {
        self.lastFlash = lastFlash
    }

    public func nextFlash<G: RandomNumberGenerator>(after date: Date, using generator: inout G) -> Date {
        let proposed = date.addingTimeInterval(.random(in: Self.minimumInterval...Self.maximumInterval, using: &generator))
        guard let lastFlash else { return proposed }
        return max(proposed, lastFlash.addingTimeInterval(Self.minimumInterval))
    }

    public func nextFlash(after date: Date) -> Date {
        var generator = SystemRandomNumberGenerator()
        return nextFlash(after: date, using: &generator)
    }

    public mutating func recordFlash(at date: Date) {
        lastFlash = date
    }
}
