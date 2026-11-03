import Foundation
import Observation

public enum RadarPhase: Hashable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
}

private let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

/// Loads radar frames and tiles for the viewport into `store` while `run()` runs. The app sets
/// `viewport`, draws `tiles` of a ready frame from `store`, and redraws when `revision` changes.
@MainActor
@Observable
public final class RadarController {
    public private(set) var phase: RadarPhase = .idle
    /// Who to credit on screen, for example "Iowa Environmental Mesonet".
    public private(set) var credit: String?
    /// Oldest first.
    public private(set) var frames: [RadarFrame] = []
    /// Frames whose tiles have all resolved, stored or known empty; the loop plays only these.
    public private(set) var readyFrameIDs: Set<String> = []
    public private(set) var zoom = 0
    public private(set) var tiles: [TileCoordinate] = []
    /// Bumps whenever tiles arrive.
    public private(set) var revision = 0
    /// Changing it while `run()` runs lays the tiles out again and fetches what is missing.
    public var viewport: RadarViewport? {
        didSet {
            guard viewport != oldValue else { return }
            viewportChanged()
        }
    }

    public let store = RadarTileStore()

    /// The wait before retrying a failed index or failed tiles.
    public static let retryDelay: TimeInterval = 60
    /// Failures in a row before a provider with frames on screen gives way to the next one. A
    /// provider with nothing on screen gives way at its first failure.
    public static let failoverAfter = 3
    /// How long a provider that gave way is skipped.
    public static let failoverDuration: TimeInterval = 15 * 60
    /// Radar older than this is not worth showing: an index whose newest frame is older counts as a
    /// failure, and when every provider fails, frames on screen are dropped once they reach this age.
    public static let staleAfter: TimeInterval = 60 * 60
    public static let failureMessage = "Radar unavailable"

    enum TileOutcome: Hashable, Sendable {
        case stored(Data)
        case empty
        case failed
        case cancelled
    }

    private struct ProviderHealth {
        var failures = 0
        var skippedUntil: Date?
        var pacer: RequestPacer
    }

    private enum Attempt {
        case done(wake: Date)
        case failed
        case cancelled
    }

    private enum SyncResult {
        case complete
        case incomplete
        case providerFailed
        case cancelled
    }

    @ObservationIgnored private let providers: [any RadarTileProvider]
    @ObservationIgnored private let fetch: RadarFetch
    @ObservationIgnored private let clock: any WeatherClock
    @ObservationIgnored private var health: [ProviderHealth]
    /// The provider `frames` came from.
    @ObservationIgnored private var active: Int?
    @ObservationIgnored private var nextIndexFetch: Date?
    @ObservationIgnored private var failure: String?
    @ObservationIgnored private var runCount = 0
    @ObservationIgnored private var cycleTask: Task<Date, Never>?
    @ObservationIgnored private var sleeper: Task<Void, any Error>?
    /// Set while the loop sleeps between cycles.
    @ObservationIgnored private(set) var sleepingUntil: Date?

    /// `providers` in order of preference.
    public init(
        viewport: RadarViewport? = nil,
        providers: [any RadarTileProvider] = [IEMRadarProvider(), RainViewerRadarProvider()],
        fetch: @escaping RadarFetch = RadarNetwork.fetch,
        clock: any WeatherClock = SystemWeatherClock()
    ) {
        self.providers = providers
        self.fetch = fetch
        self.clock = clock
        health = providers.map { ProviderHealth(pacer: RequestPacer(perMinute: $0.requestLimit.perMinute)) }
        self.viewport = viewport
        layoutTiles()
    }

    /// The frames the loop can play, oldest first.
    public var readyFrames: [RadarFrame] {
        frames.filter { readyFrameIDs.contains($0.id) }
    }

    /// Loads, refreshes and retries until the calling task is cancelled. Frames and tiles stay in
    /// `store` afterwards, so the next run fetches only what is new.
    public func run() async {
        runCount += 1
        failure = nil
        updatePhase()
        while !Task.isCancelled {
            let cycle = Task { await self.cycle() }
            cycleTask = cycle
            let wake = await withTaskCancellationHandler {
                await cycle.value
            } onCancel: {
                cycle.cancel()
            }
            if cycleTask == cycle { cycleTask = nil }
            guard !Task.isCancelled else { break }
            await sleep(until: wake)
        }
        runCount -= 1
        updatePhase()
    }

    private func cycle() async -> Date {
        guard let viewport else { return clock.now.addingTimeInterval(3600) }
        for index in candidates(for: viewport.center, at: clock.now) {
            switch await attempt(index) {
            case .done(let wake): return wake
            case .cancelled: return clock.now
            case .failed: continue
            }
        }
        return everyProviderFailed()
    }

    private func candidates(for center: GeoPoint, at now: Date) -> [Int] {
        providers.indices.filter { index in
            providers[index].covers(center) && (health[index].skippedUntil.map { $0 <= now } ?? true)
        }
    }

    private func attempt(_ index: Int) async -> Attempt {
        let provider = providers[index]
        if index != active || nextIndexFetch.map({ $0 <= clock.now }) ?? true {
            let fetched: [RadarFrame]
            do {
                try await pace(index)
                fetched = try await provider.frames(using: fetch)
                guard let newest = fetched.last else { throw RadarProviderError.badIndex }
                guard clock.now.timeIntervalSince(newest.time) <= Self.staleAfter else { throw RadarProviderError.staleIndex }
            } catch {
                if Task.isCancelled { return .cancelled }
                if index == active { nextIndexFetch = clock.now.addingTimeInterval(Self.retryDelay) }
                return recordFailure(index)
            }
            if Task.isCancelled { return .cancelled }
            adopt(fetched, from: index)
            nextIndexFetch = clock.now.addingTimeInterval(provider.refreshInterval)
        }
        let result = await syncTiles(index)
        let now = clock.now
        switch result {
        case .cancelled:
            return .cancelled
        case .providerFailed:
            return recordFailure(index)
        case .complete, .incomplete:
            health[index].failures = 0
            failure = nil
            updatePhase()
            var wake = nextIndexFetch ?? now
            if result == .incomplete { wake = min(wake, now.addingTimeInterval(Self.retryDelay)) }
            if let comeback = comeback(before: index) { wake = min(wake, comeback) }
            return .done(wake: wake)
        }
    }

    private func recordFailure(_ index: Int) -> Attempt {
        health[index].failures += 1
        let now = clock.now
        if index == active, !readyFrameIDs.isEmpty, health[index].failures < Self.failoverAfter {
            return .done(wake: now.addingTimeInterval(Self.retryDelay))
        }
        health[index].skippedUntil = now.addingTimeInterval(Self.failoverDuration)
        return .failed
    }

    /// When a preferred provider that gave way may be tried again.
    private func comeback(before index: Int) -> Date? {
        guard let center = viewport?.center else { return nil }
        return providers.indices.prefix(index)
            .filter { providers[$0].covers(center) }
            .compactMap { health[$0].skippedUntil }
            .min()
    }

    /// Starts the chain again from the most preferred provider after a pause.
    private func everyProviderFailed() -> Date {
        let now = clock.now
        for index in health.indices { health[index].skippedUntil = nil }
        if let newest = frames.last, now.timeIntervalSince(newest.time) > Self.staleAfter {
            dropFrames()
            layoutTiles()
        }
        failure = Self.failureMessage
        updatePhase()
        return now.addingTimeInterval(Self.retryDelay)
    }

    private func adopt(_ fetched: [RadarFrame], from index: Int) {
        if fetched != frames { frames = fetched }
        if index != active {
            active = index
            credit = providers[index].credit
        }
        layoutTiles()
    }

    /// Newest frame first so the loop can start, then older ones.
    private func syncTiles(_ index: Int) async -> SyncResult {
        let layout = tiles
        var judged = false
        var complete = true
        for frame in frames.reversed() {
            let missing = layout.filter { !store.isResolved(frame: frame.id, tile: $0) }
            guard !missing.isEmpty else { continue }
            let failed = await fetchTiles(missing, of: frame, from: index)
            if Task.isCancelled { return .cancelled }
            if failed > 0 { complete = false }
            // Most of a mostly unfetched frame failing means the provider is down; a few tiles
            // retried from an earlier pass say nothing about it.
            if !judged, missing.count * 2 > layout.count {
                judged = true
                if failed * 2 > missing.count { return .providerFailed }
            }
        }
        return complete ? .complete : .incomplete
    }

    /// Returns how many tiles failed.
    private func fetchTiles(_ missing: [TileCoordinate], of frame: RadarFrame, from index: Int) async -> Int {
        let provider = providers[index]
        let concurrent = max(provider.requestLimit.concurrent, 1)
        let fetch = fetch
        let clock = clock
        var queue = missing[...]
        var failed = 0
        await withTaskGroup(of: (TileCoordinate, TileOutcome).self) { group in
            var running = 0
            while true {
                while running < concurrent, !Task.isCancelled, let tile = queue.popFirst() {
                    guard let url = provider.tileURL(frame: frame, tile: tile) else {
                        failed += 1
                        continue
                    }
                    let start = health[index].pacer.reserve(at: clock.now)
                    running += 1
                    group.addTask {
                        (tile, await RadarController.loadTile(url, at: start, fetch: fetch, clock: clock))
                    }
                }
                guard let result = await group.next() else { break }
                running -= 1
                let (tile, outcome) = result
                switch outcome {
                case .stored(let data):
                    guard isLaidOut(frame.id, tile) else { break }
                    store.insert(data, frame: frame.id, tile: tile)
                    revision += 1
                    tileResolved(in: frame.id)
                case .empty:
                    guard isLaidOut(frame.id, tile) else { break }
                    store.markEmpty(frame: frame.id, tile: tile)
                    tileResolved(in: frame.id)
                case .failed:
                    failed += 1
                case .cancelled:
                    break
                }
            }
        }
        return failed
    }

    nonisolated private static func loadTile(_ url: URL, at start: Date, fetch: RadarFetch, clock: any WeatherClock) async -> TileOutcome {
        do {
            if start > clock.now { try await clock.sleep(until: start) }
            return outcome(of: try await fetch(url))
        } catch {
            return Task.isCancelled ? .cancelled : .failed
        }
    }

    /// A 404, a 204 or an empty body is a tile with no echoes; anything but a PNG is a failure.
    nonisolated static func outcome(of response: RadarResponse) -> TileOutcome {
        switch response.status {
        case 200 where response.data.isEmpty, 204, 404: .empty
        case 200 where response.data.starts(with: pngSignature): .stored(response.data)
        default: .failed
        }
    }

    private func pace(_ index: Int) async throws {
        let start = health[index].pacer.reserve(at: clock.now)
        if start > clock.now { try await clock.sleep(until: start) }
    }

    /// A tile that arrives after the frames or layout moved on is not kept.
    private func isLaidOut(_ frame: String, _ tile: TileCoordinate) -> Bool {
        frames.contains { $0.id == frame } && tiles.contains(tile)
    }

    private func tileResolved(in frame: String) {
        guard !readyFrameIDs.contains(frame), isComplete(frame) else { return }
        readyFrameIDs.insert(frame)
        updatePhase()
    }

    private func isComplete(_ frame: String) -> Bool {
        !tiles.isEmpty && tiles.allSatisfy { store.isResolved(frame: frame, tile: $0) }
    }

    private func viewportChanged() {
        if let active, let center = viewport?.center, !providers[active].covers(center) {
            dropFrames()
        }
        layoutTiles()
        cycleTask?.cancel()
        sleeper?.cancel()
    }

    private func dropFrames() {
        active = nil
        credit = nil
        nextIndexFetch = nil
        if !frames.isEmpty { frames = [] }
        store.keep(frames: [])
    }

    /// Lays tiles out for the provider of the current frames, or the one the next cycle will try,
    /// and drops stored tiles that no longer apply.
    private func layoutTiles() {
        guard let viewport, let provider = layoutProvider(for: viewport.center) else {
            if zoom != 0 { zoom = 0 }
            if !tiles.isEmpty { tiles = [] }
            recomputeReadiness()
            return
        }
        let z = TileMath.zoom(for: viewport, in: provider.zoomRange)
        let layout = TileMath.tiles(covering: viewport.bounds, z: z)
        if z != zoom { zoom = z }
        if layout != tiles { tiles = layout }
        store.keep(frames: Set(frames.map(\.id)), tiles: Set(layout))
        recomputeReadiness()
    }

    private func layoutProvider(for center: GeoPoint) -> (any RadarTileProvider)? {
        if let active { return providers[active] }
        return providers.first { $0.covers(center) }
    }

    private func recomputeReadiness() {
        let ready = Set(frames.map(\.id).filter(isComplete))
        if ready != readyFrameIDs { readyFrameIDs = ready }
        updatePhase()
    }

    private func updatePhase() {
        let next: RadarPhase =
            if !readyFrameIDs.isEmpty { .ready }
            else if let failure { .failed(failure) }
            else if runCount > 0 { .loading }
            else { .idle }
        if next != phase { phase = next }
    }

    private func sleep(until deadline: Date) async {
        let clock = clock
        let task = Task { try await clock.sleep(until: deadline) }
        sleeper = task
        sleepingUntil = deadline
        await withTaskCancellationHandler {
            _ = try? await task.value
        } onCancel: {
            task.cancel()
        }
        sleepingUntil = nil
        if sleeper == task { sleeper = nil }
    }
}
