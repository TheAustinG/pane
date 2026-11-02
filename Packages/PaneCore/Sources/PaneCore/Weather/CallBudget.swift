import Foundation
import Synchronization

/// Small persistent values, so the call budget survives relaunches.
public protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public struct UserDefaultsKeyValueStore: KeyValueStore {
    // Apple documents UserDefaults as thread-safe; the SDK just does not mark it Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

public final class InMemoryKeyValueStore: KeyValueStore {
    private let values = Mutex<[String: Data]>([:])

    public init() {}

    public func data(forKey key: String) -> Data? {
        values.withLock { $0[key] }
    }

    public func set(_ data: Data?, forKey key: String) {
        values.withLock { $0[key] = data }
    }
}

/// Billable WeatherKit calls this calendar month. WeatherKit includes 500,000 a month; past the
/// soft limit the controller refreshes less often.
public struct CallBudget: Sendable {
    public static let defaultSoftLimit = 45_000

    public let softLimit: Int
    private let store: any KeyValueStore
    private let calendar: Calendar
    private let key: String

    public init(
        store: any KeyValueStore = UserDefaultsKeyValueStore(),
        calendar: Calendar = .current,
        softLimit: Int = defaultSoftLimit,
        key: String = "weather.callBudget"
    ) {
        self.store = store
        self.calendar = calendar
        self.softLimit = softLimit
        self.key = key
    }

    public func calls(at date: Date) -> Int {
        guard let record = load(), record.month == month(of: date) else { return 0 }
        return record.calls
    }

    @discardableResult
    public func record(_ calls: Int, at date: Date) -> Int {
        let total = self.calls(at: date) + calls
        guard calls > 0 else { return total }
        if let data = try? JSONEncoder().encode(Record(month: month(of: date), calls: total)) {
            store.set(data, forKey: key)
        }
        return total
    }

    public func isOverSoftLimit(at date: Date) -> Bool {
        calls(at: date) >= softLimit
    }

    func month(of date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    private struct Record: Codable {
        var month: String
        var calls: Int
    }

    private func load() -> Record? {
        store.data(forKey: key).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }
}
