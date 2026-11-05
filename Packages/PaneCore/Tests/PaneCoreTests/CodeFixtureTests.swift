import Foundation
import Synchronization
import Testing
@testable import PaneCore

/// Scrubbed GitHub and Portainer replies from `Fixtures/`, and invented values around them.
enum CodeSample {
    static let login = "sample-user"
    static let githubToken = "sample-github-token"
    static let portainerToken = "sample-portainer-token"
    static let server = PortainerServer(address: "https://portainer.fixture.invalid:9443", environmentID: 3)!
    static let pinnedServer = PortainerServer(
        address: "https://portainer.fixture.invalid:9443",
        environmentID: 3,
        pinnedCertificateSHA256: String(repeating: "ab", count: 32)
    )!
    /// 2026-11-03 21:00 in Chicago, an hour after the newest push in the fixtures.
    static let start = WeatherFixture.local(2026, 11, 3, 21)
    static let calendar = WeatherFixture.calendar

    static let beacon = DeployTarget(repository: "sample-user/beacon", workflow: "publish.yml", containerName: "beacon-beacon-1")
    static let ledger = DeployTarget(repository: "sample-user/ledger", workflow: "publish.yml", containerName: "ledger")
    /// The newest successful ledger publish run in `github-runs-ledger.json`.
    static let ledgerBuiltAt = date("2026-09-29T02:36:44Z")
    static let beaconBuiltAt = date("2026-09-26T05:17:29Z")
    static let latestSHA = "8eb48593be61f4aea40289948a11b28a4010db0c"
    static let latestHeadline = "Add the porch light card and its sample data."

    static func data(_ name: String, _ ext: String = "json") -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }

    static func date(_ text: String) -> Date {
        CodeDate.parse(text)!
    }

    static var containers: [PortainerContainer] {
        try! PortainerClient.parseContainers(data("portainer-containers"))
    }

    static func container(
        _ name: String,
        repository: String? = "sample-user/beacon",
        revision: String? = nil,
        created: String? = nil,
        state: String = "running",
        imageID: String = "sha256:" + String(repeating: "c", count: 64)
    ) -> PortainerContainer {
        var labels: [String: String] = [:]
        if let repository { labels[RevisionComparison.sourceLabel] = "https://github.com/\(repository)" }
        if let revision { labels[RevisionComparison.revisionLabel] = revision }
        if let created { labels[RevisionComparison.createdLabel] = created }
        return PortainerContainer(
            id: String(repeating: "d", count: 64),
            name: name,
            image: "ghcr.io/\(repository ?? "example/none"):latest",
            imageID: imageID,
            state: state,
            created: date("2026-11-01T16:18:00Z"),
            labels: labels
        )
    }

    /// Every route the controller reads on a full pass, answered from the fixtures.
    static func routes(_ http: FakeHTTP) {
        http.set(FakeHTTP.viewer, fixture: "github-viewer")
        http.set(FakeHTTP.login, fixture: "github-viewer")
        http.set("/repos/sample-user/lantern/activity", fixture: "github-activity")
        http.set("/repos/sample-user/lantern/commits/\(latestSHA)", fixture: "github-commit")
        http.set("/repos/sample-user/beacon/actions/workflows", fixture: "github-workflows")
        http.set("/repos/sample-user/ledger/actions/workflows", fixture: "github-workflows")
        http.set("/repos/sample-user/beacon/actions/workflows/publish.yml/runs", fixture: "github-runs-beacon")
        http.set("/repos/sample-user/ledger/actions/workflows/publish.yml/runs", fixture: "github-runs-ledger")
    }

    static func portainerRoutes(_ http: FakeHTTP) {
        http.set("/api/system/status", fixture: "portainer-status")
        http.set("/api/endpoints/3/docker/containers/json", fixture: "portainer-containers")
    }
}

/// Answers requests by path from a table, records every request, and can fail them all.
final class FakeHTTP: HTTPClient {
    struct Response {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]
    }

    /// GraphQL requests are keyed by which query they carry.
    static let viewer = "/graphql#viewer"
    static let login = "/graphql#login"

    private struct State {
        var routes: [String: Response] = [:]
        var requests: [URLRequest] = []
        var failure: (any Error)?
        var held: Set<String> = []
        var parked: [String: [CheckedContinuation<Void, Never>]] = [:]
        var watchers: [String: [CheckedContinuation<Void, Never>]] = [:]
    }

    private let state = Mutex(State())

    init() {}

    func set(_ key: String, _ response: Response) {
        state.withLock { $0.routes[key] = response }
    }

    func set(_ key: String, fixture: String, status: Int = 200) {
        set(key, Response(status: status, body: CodeSample.data(fixture)))
    }

    func set(_ key: String, status: Int, json: String = "{}", headers: [String: String] = [:]) {
        set(key, Response(status: status, body: Data(json.utf8), headers: headers))
    }

    /// Requests to `key` wait, with the reply they would get now, until `release`.
    func hold(_ key: String) {
        state.withLock { _ = $0.held.insert(key) }
    }

    func release(_ key: String) {
        let parked = state.withLock { state in
            state.held.remove(key)
            return state.parked.removeValue(forKey: key) ?? []
        }
        parked.forEach { $0.resume() }
    }

    /// Returns once a request to `key` is waiting on `hold`.
    func waitForHeldRequest(_ key: String) async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state in
                if state.parked[key]?.isEmpty == false { return true }
                state.watchers[key, default: []].append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func remove(_ key: String) {
        state.withLock { $0.routes[key] = nil }
    }

    func fail(with error: (any Error)?) {
        state.withLock { $0.failure = error }
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }
    var keys: [String] { requests.map(Self.key) }
    var count: Int { state.withLock { $0.requests.count } }

    func count(_ key: String) -> Int {
        keys.filter { $0 == key }.count
    }

    static func key(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        guard path == "/graphql" else { return path }
        let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        return body.contains("contributionsCollection") ? viewer : login
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = Self.key(request)
        let (response, failure, isHeld) = state.withLock { state -> (Response?, (any Error)?, Bool) in
            state.requests.append(request)
            return (state.routes[key], state.failure, state.held.contains(key))
        }
        if isHeld {
            await withCheckedContinuation { continuation in
                let watchers = state.withLock { state in
                    state.parked[key, default: []].append(continuation)
                    return state.watchers.removeValue(forKey: key) ?? []
                }
                watchers.forEach { $0.resume() }
            }
        }
        if let failure { throw failure }
        let reply = response ?? Response(status: 404, body: Data(#"{"message":"Not Found"}"#.utf8))
        let http = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (reply.body, http)
    }
}

/// A controller on fake GitHub and Portainer servers, a stepping clock and in-memory stores.
@MainActor
final class CodeHarness {
    let clock: SteppingClock
    let github: FakeHTTP
    let portainer: FakeHTTP
    let store: InMemoryKeyValueStore
    let secrets: InMemorySecretStore
    let controller: CodeController
    private let servers = ServerLog()
    private var task: Task<Void, Never>?

    init(
        configureGitHub: Bool = true,
        configurePortainer: Bool = true,
        routes: Bool = true,
        store: InMemoryKeyValueStore = InMemoryKeyValueStore(),
        secrets: InMemorySecretStore = InMemorySecretStore(),
        portainerHTTP: FakeHTTP = FakeHTTP()
    ) {
        let clock = SteppingClock(now: CodeSample.start)
        self.clock = clock
        github = FakeHTTP()
        portainer = portainerHTTP
        self.store = store
        self.secrets = secrets
        if routes {
            CodeSample.routes(github)
            CodeSample.portainerRoutes(portainer)
        }
        let portainer = portainer
        let servers = servers
        controller = CodeController(
            store: store,
            secrets: secrets,
            http: github,
            portainerHTTP: { server in
                servers.append(server)
                return portainer
            },
            clock: clock,
            backoff: ReconnectBackoff(initial: 60, maximum: 15 * 60, jitter: 0)
        )
        controller.calendar = CodeSample.calendar
        controller.now = { clock.now }
        if configureGitHub { try! controller.configureGitHub(token: CodeSample.githubToken) }
        if configurePortainer { try! controller.configurePortainer(server: CodeSample.server, token: CodeSample.portainerToken) }
    }

    /// Servers the controller asked for an HTTP client for, in order.
    var portainerServers: [PortainerServer] { servers.all }

    func launch() {
        let controller = controller
        task = Task { await controller.run() }
    }

    /// Launches and waits for both first refreshes and their next scheduled ones.
    func refreshBoth() async {
        launch()
        await waitUntil { self.controller.githubConnection == .ready && self.controller.portainerConnection == .ready }
        await clock.waitForSleeper(until: clock.now.addingTimeInterval(CodeController.githubInterval))
        await clock.waitForSleeper(until: clock.now.addingTimeInterval(CodeController.deployInterval))
    }

    func stop() async {
        task?.cancel()
        await task?.value
        task = nil
    }
}

final class ServerLog: Sendable {
    private let servers = Mutex<[PortainerServer]>([])

    var all: [PortainerServer] { servers.withLock { $0 } }

    func append(_ server: PortainerServer) {
        servers.withLock { $0.append(server) }
    }
}

@Suite("Code fixtures")
struct CodeFixtureTests {
    @Test func fixturesCarryNoRealNames() throws {
        let names = [
            "github-viewer", "github-activity", "github-activity-deletion-first", "github-commit", "github-workflows",
            "github-runs-beacon", "github-runs-ledger", "github-graphql-error", "github-bad-credentials",
            "portainer-status", "portainer-containers", "portainer-image", "portainer-unknown-environment", "portainer-bad-key",
        ]
        for name in names {
            let text = String(decoding: CodeSample.data(name), as: UTF8.self)
            #expect(!text.isEmpty)
            #expect(!text.contains("\u{2014}"), "\(name) has an em dash")
            #expect(text.range(of: #"\b(10|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d+\.\d+"#, options: .regularExpression) == nil, "\(name) has a private address")
        }
    }

    @Test func previewServesTheRealRoutes() async throws {
        let snapshot = GitHubSnapshot(
            login: "sample",
            calendar: ContributionCalendar(days: [ContributionDay(day: CalendarDay(year: 2026, month: 11, day: 1), count: 3, level: 2)]),
            latestCommit: LatestCommit(repository: "sample/kite", branch: "main", sha: "abcdef1234567", headline: "Sample", date: CodeSample.start),
            fetchedAt: CodeSample.start
        )
        let fixture = CodeFixtureHTTPClient(github: snapshot, containers: [], runs: [])
        let client = GitHubClient(http: fixture, token: CodeFixtureHTTPClient.githubToken)
        let viewer = try await client.viewer()
        #expect(viewer.login == "sample")
        #expect(viewer.calendar == snapshot.calendar)
        let latest = try await client.latestCommit(repositories: viewer.repositories, previous: nil)
        #expect(latest == snapshot.latestCommit)

        let wrongToken = GitHubClient(http: fixture, token: "nope")
        await #expect(throws: GitHubError.unauthorized) { try await wrongToken.viewer() }

        let portainer = PortainerClient(http: fixture, server: CodeFixtureHTTPClient.server, token: CodeFixtureHTTPClient.portainerToken)
        #expect(try await portainer.version() == CodeFixtureHTTPClient.portainerVersion)
        #expect(try await portainer.containers() == [])
        let otherEnvironment = PortainerClient(
            http: fixture,
            server: PortainerServer(address: "https://fixture.invalid", environmentID: 2)!,
            token: CodeFixtureHTTPClient.portainerToken
        )
        await #expect(throws: PortainerError.notFound) { try await otherEnvironment.containers() }
    }
}
