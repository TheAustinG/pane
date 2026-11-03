import Foundation

/// Wall-clock time and waiting for the weather controller, so tests can drive a month of refreshes
/// without sleeping.
public protocol WeatherClock: Sendable {
    var now: Date { get }
    /// Returns at `deadline`, or throws `CancellationError` when the calling task is cancelled.
    func sleep(until deadline: Date) async throws
}

public struct SystemWeatherClock: WeatherClock {
    public init() {}

    public var now: Date { .now }

    public func sleep(until deadline: Date) async throws {
        try await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
    }
}

/// Fetches the bytes at a URL; the controller uses it for the Apple Weather mark image.
public typealias WeatherDataLoader = @Sendable (URL) async throws -> Data

public enum WeatherDownload {
    public static func data(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
