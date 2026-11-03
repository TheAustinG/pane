import Foundation
import Testing
@testable import PaneCore

@Suite("Weather cache")
struct WeatherCacheTests {
    private let report = WeatherFixture.report(at: WeatherFixture.local(2026, 11, 2, 14))
    private let fetchedAt = WeatherFixture.local(2026, 11, 2, 9)

    private func roundTrip(_ cache: WeatherCache) {
        #expect(cache.loadReport() == nil)
        #expect(cache.loadAttribution() == nil)
        #expect(cache.loadMark() == nil)
        cache.save(report)
        cache.save(WeatherFixture.attribution, fetchedAt: fetchedAt)
        cache.saveMark(MarkLoader.png)
        #expect(cache.loadReport() == report)
        #expect(cache.loadAttribution() == CachedAttribution(info: WeatherFixture.attribution, fetchedAt: fetchedAt))
        #expect(cache.loadMark() == MarkLoader.png)
    }

    @Test func inMemoryRoundTrip() {
        roundTrip(.inMemory())
    }

    @Test func directoryRoundTripSurvivesReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pane-weather-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        roundTrip(WeatherCache(directory: directory))
        let reopened = WeatherCache(directory: directory)
        #expect(reopened.loadReport() == report)
        #expect(reopened.loadMark() == MarkLoader.png)
        let json = try String(contentsOf: directory.appending(path: "report.json"), encoding: .utf8)
        #expect(json.contains("\"fetchedAt\":\"2026-11-02T20:00:00Z\""))
    }

    @Test func unreadableFilesLoadAsNothing() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "pane-weather-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "report.json"))
        #expect(WeatherCache(directory: directory).loadReport() == nil)
    }

    @Test func defaultDirectoryIsInCaches() {
        #expect(WeatherCache.defaultDirectory.lastPathComponent == "Weather")
        #expect(WeatherCache.defaultDirectory.deletingLastPathComponent() == URL.cachesDirectory)
    }
}
