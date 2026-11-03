import Foundation

/// Playback position in the radar loop: each frame for `frameDuration`, the newest held for
/// `newestHold`, then back to the oldest.
public struct RadarLoop: Hashable, Sendable {
    public static let frameDuration: Duration = .milliseconds(500)
    public static let newestHold: Duration = .seconds(2)

    public private(set) var index = 0

    public init(index: Int = 0) {
        self.index = index
    }

    public mutating func advance(frameCount: Int) {
        guard frameCount > 0 else {
            index = 0
            return
        }
        index = (index + 1) % frameCount
    }

    /// How long the current frame stays up.
    public func delay(frameCount: Int) -> Duration {
        index >= frameCount - 1 ? Self.newestHold : Self.frameDuration
    }
}
