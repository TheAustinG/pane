import Foundation
import Synchronization

/// The last report, the attribution and the mark image, so the cards and the Apple Weather mark
/// show at launch even with no network.
public struct WeatherCache: Sendable {
    private let storage: any WeatherCacheStorage

    public init(directory: URL) {
        storage = DirectoryCacheStorage(directory: directory)
    }

    private init(storage: any WeatherCacheStorage) {
        self.storage = storage
    }

    public static func inMemory() -> WeatherCache {
        WeatherCache(storage: MemoryCacheStorage())
    }

    public static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "Weather", directoryHint: .isDirectory)
    }

    public func loadReport() -> WeatherReport? {
        decode(WeatherReport.self, from: Files.report)
    }

    public func save(_ report: WeatherReport) {
        encode(report, to: Files.report)
    }

    public func loadAttribution() -> CachedAttribution? {
        decode(CachedAttribution.self, from: Files.attribution)
    }

    public func save(_ attribution: WeatherAttributionInfo, fetchedAt: Date) {
        encode(CachedAttribution(info: attribution, fetchedAt: fetchedAt), to: Files.attribution)
    }

    public func loadMark() -> Data? {
        storage.read(Files.mark)
    }

    public func saveMark(_ data: Data) {
        storage.write(data, to: Files.mark)
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private enum Files {
        static let report = "report.json"
        static let attribution = "attribution.json"
        static let mark = "mark-dark.png"
    }

    private func decode<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        storage.read(name).flatMap { try? Self.makeDecoder().decode(type, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T, to name: String) {
        if let data = try? Self.makeEncoder().encode(value) {
            storage.write(data, to: name)
        }
    }
}

public struct CachedAttribution: Codable, Hashable, Sendable {
    public var info: WeatherAttributionInfo
    public var fetchedAt: Date

    public init(info: WeatherAttributionInfo, fetchedAt: Date) {
        self.info = info
        self.fetchedAt = fetchedAt
    }
}

protocol WeatherCacheStorage: Sendable {
    func read(_ name: String) -> Data?
    func write(_ data: Data, to name: String)
}

private struct DirectoryCacheStorage: WeatherCacheStorage {
    let directory: URL

    func read(_ name: String) -> Data? {
        try? Data(contentsOf: directory.appending(path: name))
    }

    func write(_ data: Data, to name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: name), options: .atomic)
    }
}

private final class MemoryCacheStorage: WeatherCacheStorage {
    private let files = Mutex<[String: Data]>([:])

    func read(_ name: String) -> Data? {
        files.withLock { $0[name] }
    }

    func write(_ data: Data, to name: String) {
        files.withLock { $0[name] = data }
    }
}
