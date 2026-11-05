import Foundation
import Observation

/// Owns the Code card's data: the GitHub token and snapshot (contribution calendar, latest
/// commit), the Portainer server and token, the deploy targets, and the "built, not redeployed"
/// nudges they raise. The app reads it.
@MainActor
@Observable
public final class CodeController {
    public private(set) var githubConnection: CodeConnection = .notConfigured
    /// The last good snapshot, kept through failures and across launches.
    public private(set) var github: GitHubSnapshot?

    public private(set) var portainer: PortainerServer?
    public private(set) var portainerConnection: CodeConnection = .notConfigured
    /// The latest comparison for each target in `activeTargets`.
    public private(set) var deploys: [DeployStatus] = []
    /// Containers built from one of the viewer's repositories, found on the last refresh, each as a
    /// target with its publish workflow guessed. Settings offers them.
    public private(set) var candidates: [DeployTarget] = []

    /// Why GitHub last failed, when it can be named (a refused token, a missing Actions
    /// permission); nil after a good refresh.
    public private(set) var githubProblem: CodeSetupError?
    /// Why Portainer last failed, such as `.certificateChanged`; nil after a good refresh.
    public private(set) var portainerProblem: CodeSetupError?
    /// When `deploys` was last worked out from a good Portainer read.
    public private(set) var deploysCheckedAt: Date?
    /// Requests sent since launch, for the soak log.
    public private(set) var githubRequestCount = 0
    public private(set) var portainerRequestCount = 0

    /// The owner's chosen targets; nil watches every candidate.
    public var targets: [DeployTarget]? = nil {
        didSet {
            guard targets != oldValue else { return }
            store.set(targets.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.targets)
            restartDeploys()
            if !lastContainers.isEmpty { recomputeDeploys() }
        }
    }
    /// Off hides the deploy nudge without stopping the checks.
    public var nudgeEnabled = true {
        didSet {
            guard nudgeEnabled != oldValue else { return }
            save(nudgeEnabled, forKey: Keys.nudgeEnabled)
        }
    }
    /// Debug: true raises a nudge on the first target, false hides every nudge, nil shows live state.
    public var debugNudge: Bool?
    /// App time for "today" and nudge ages; the app points it at its debug clock.
    @ObservationIgnored public var now: @MainActor () -> Date = { .now }
    /// Contribution days are counted in this calendar's time zone.
    @ObservationIgnored public var calendar: Calendar = .current

    static let githubInterval: TimeInterval = 10 * 60
    static let deployInterval: TimeInterval = 5 * 60
    /// How often an idle loop (no token, or a refused one) wakes to look again.
    static let idleInterval: TimeInterval = 3600
    static let workflowLifetime: TimeInterval = 3600
    static let defaultBackoff = ReconnectBackoff(initial: 60, maximum: 15 * 60, jitter: 0.2)
    static let debugNudgeAge: TimeInterval = 3 * 3600

    enum Keys {
        static let github = "code.github"
        static let portainer = "code.portainer"
        static let targets = "code.targets"
        static let nudgeEnabled = "code.nudgeEnabled"
        static let candidates = "code.candidates"
        static let all = [github, portainer, targets, nudgeEnabled, candidates]
    }

    private enum Loop {
        case github, deploys
    }

    @ObservationIgnored private let store: any KeyValueStore
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let http: any HTTPClient
    @ObservationIgnored private let portainerHTTP: @Sendable (PortainerServer) -> any HTTPClient
    @ObservationIgnored private let clock: any WeatherClock
    @ObservationIgnored private let backoff: ReconnectBackoff
    @ObservationIgnored private let githubCounter = RequestCounter()
    @ObservationIgnored private let portainerCounter = RequestCounter()
    @ObservationIgnored private var portainerClient: (server: PortainerServer, http: any HTTPClient)?
    @ObservationIgnored private var workflowCache: [String: (fetchedAt: Date, files: [WorkflowFile])] = [:]
    @ObservationIgnored private var runCache: [RunKey: PublishRun] = [:]
    @ObservationIgnored private var imageCache: [String: PortainerImage] = [:]
    @ObservationIgnored private var lastContainers: [PortainerContainer] = []
    @ObservationIgnored private var deployLogin: String?
    @ObservationIgnored private var githubAuthRejected = false
    @ObservationIgnored private var portainerAuthRejected = false
    @ObservationIgnored private var githubPausedUntil: Date?
    @ObservationIgnored private var githubFailures = 0
    @ObservationIgnored private var githubDownSince: Date?
    @ObservationIgnored private var deployFailures = 0
    @ObservationIgnored private var portainerDownSince: Date?
    @ObservationIgnored private var githubGeneration = 0
    @ObservationIgnored private var deployGeneration = 0
    @ObservationIgnored private var sleepers: [Loop: Task<Void, any Error>] = [:]
    @ObservationIgnored private var pendingWakes: Set<Loop> = []

    public convenience init(
        store: any KeyValueStore = UserDefaultsKeyValueStore(),
        secrets: any SecretStore,
        http: any HTTPClient,
        portainerHTTP: @escaping @Sendable (PortainerServer) -> any HTTPClient,
        clock: any WeatherClock = SystemWeatherClock()
    ) {
        self.init(store: store, secrets: secrets, http: http, portainerHTTP: portainerHTTP, clock: clock, backoff: Self.defaultBackoff)
    }

    init(
        store: any KeyValueStore,
        secrets: any SecretStore,
        http: any HTTPClient,
        portainerHTTP: @escaping @Sendable (PortainerServer) -> any HTTPClient,
        clock: any WeatherClock,
        backoff: ReconnectBackoff
    ) {
        self.store = store
        self.secrets = secrets
        self.http = http
        self.portainerHTTP = portainerHTTP
        self.clock = clock
        self.backoff = backoff
        github = Self.load(GitHubSnapshot.self, from: store, key: Keys.github)
        portainer = Self.load(PortainerServer.self, from: store, key: Keys.portainer)
        targets = Self.load([DeployTarget].self, from: store, key: Keys.targets)
        nudgeEnabled = Self.load(Bool.self, from: store, key: Keys.nudgeEnabled) ?? true
        candidates = Self.load([DeployTarget].self, from: store, key: Keys.candidates) ?? []
        githubConnection = githubToken == nil ? .notConfigured : .loading
        portainerConnection = isPortainerConfigured ? .loading : .notConfigured
    }

    public var hasGitHubToken: Bool { githubToken != nil }
    public var hasPortainerToken: Bool { portainerToken != nil }

    public var activeTargets: [DeployTarget] { targets ?? candidates }

    /// Targets that are behind, after `nudgeEnabled` and `debugNudge`, newest build first.
    public var nudges: [DeployStatus] {
        // Comparisons from before a Portainer failure may no longer hold.
        if debugNudge == nil, portainerConnection != .ready { return [] }
        var statuses = deploys
        if debugNudge == true, statuses.isEmpty, let first = activeTargets.first {
            statuses = [DeployStatus(target: first, run: nil, container: nil, verdict: .unknown)]
        }
        return DeployDiscovery.nudges(
            statuses: statuses,
            enabled: nudgeEnabled,
            debugNudge: debugNudge,
            fallbackBuiltAt: now().addingTimeInterval(-Self.debugNudgeAge)
        )
    }

    /// Streak, today's count and grid levels for `weeks` columns ending at today's week.
    public func contributionSummary(weeks: Int = 26) -> ContributionSummary? {
        guard let github else { return nil }
        let today = CalendarDay(date: now(), timeZone: calendar.timeZone)
        return ContributionSummary.make(calendar: github.calendar, today: today, weeks: weeks)
    }

    /// Saves the token and refreshes with it.
    public func configureGitHub(token: String) throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousToken = try? secrets.string(for: .githubToken)
        try secrets.setString(token.isEmpty ? nil : token, for: .githubToken)
        if token != previousToken {
            // The snapshot may belong to another account, and its login feeds the deploy pass.
            github = nil
            store.set(nil, forKey: Keys.github)
            candidates = []
            deploys = []
        }
        resetGitHubState()
        githubConnection = token.isEmpty ? .notConfigured : .loading
        restartGitHub()
        restartDeploys()
    }

    /// Saves the server (with its pin) and token and refreshes with them.
    public func configurePortainer(server: PortainerServer, token: String) throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try secrets.setString(token.isEmpty ? nil : token, for: .portainerToken)
        if server.baseURL != portainer?.baseURL || server.environmentID != portainer?.environmentID {
            deploys = []
            lastContainers = []
            imageCache = [:]
            deploysCheckedAt = nil
        }
        portainer = server
        save(server, forKey: Keys.portainer)
        resetPortainerState()
        portainerConnection = isPortainerConfigured ? .loading : .notConfigured
        restartDeploys()
    }

    public func forgetGitHub() throws {
        try secrets.setString(nil, for: .githubToken)
        github = nil
        store.set(nil, forKey: Keys.github)
        resetGitHubState()
        githubConnection = .notConfigured
        restartGitHub()
        restartDeploys()
    }

    public func forgetPortainer() throws {
        try secrets.setString(nil, for: .portainerToken)
        portainer = nil
        store.set(nil, forKey: Keys.portainer)
        targets = nil
        candidates = []
        store.set(nil, forKey: Keys.candidates)
        deploys = []
        lastContainers = []
        imageCache = [:]
        deploysCheckedAt = nil
        resetPortainerState()
        portainerConnection = .notConfigured
        restartDeploys()
    }

    /// Clears everything `CodeController` saves, for the app's `-resetSettings`.
    public static func reset(store: any KeyValueStore = UserDefaultsKeyValueStore(), secrets: any SecretStore) {
        Keys.all.forEach { store.set(nil, forKey: $0) }
        try? secrets.setString(nil, for: .githubToken)
        try? secrets.setString(nil, for: .portainerToken)
    }

    /// Refreshes GitHub and the deploy targets on a timer, backing off after failures. Runs until
    /// the calling task is cancelled.
    public func run() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.githubLoop() }
            group.addTask { await self.deployLoop() }
        }
    }

    /// Starts the next refresh now instead of at its scheduled time.
    public func refreshNow() {
        wake(.github)
        wake(.deploys)
    }

    /// The GitHub setup screen's test: returns the token's login.
    public static func testGitHub(token: String, http: any HTTPClient) async -> Result<String, CodeSetupError> {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return .failure(.invalidToken) }
        let client = GitHubClient(http: http, token: token)
        do {
            let viewer = try await client.login()
            if let repository = viewer.repositories.first {
                do {
                    _ = try await client.workflows(repository: repository.nameWithOwner)
                } catch GitHubError.forbidden, GitHubError.notFound {
                    return .failure(.missingPermission("Actions"))
                }
            }
            return .success(viewer.login)
        } catch {
            return .failure(setupError(error))
        }
    }

    /// The Portainer setup screen's test: reads the version and container list, and reports the
    /// certificate's SHA-256 when the system does not trust it.
    public static func testPortainer(server: PortainerServer, token: String) async -> Result<PortainerServerInfo, CodeSetupError> {
        let client = PortainerHTTPClient(server: server, trustOnFirstUse: server.pinnedCertificateSHA256 == nil)
        return await testPortainer(server: server, token: token, http: client) { client.observedCertificateSHA256 }
    }

    static func testPortainer(
        server: PortainerServer,
        token: String,
        http: any HTTPClient,
        observedCertificate: @Sendable () -> String?
    ) async -> Result<PortainerServerInfo, CodeSetupError> {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return .failure(.invalidToken) }
        let client = PortainerClient(http: http, server: server, token: token)
        let version: String
        do {
            version = try await client.version()
        } catch PortainerError.notFound, PortainerError.malformed {
            return .failure(.unexpectedReply("Not a Portainer server"))
        } catch {
            return .failure(setupError(error))
        }
        do {
            let containers = try await client.containers()
            return .success(PortainerServerInfo(version: version, containerCount: containers.count, certificateSHA256: observedCertificate()))
        } catch {
            return .failure(setupError(error))
        }
    }

    /// A controller on the real code path against recorded-style responses built from these
    /// values. The caller still runs it.
    public static func preview(
        github: GitHubSnapshot,
        containers: [PortainerContainer],
        runs: [PublishRun],
        targets: [DeployTarget]? = nil
    ) -> CodeController {
        let fixture = CodeFixtureHTTPClient(github: github, containers: containers, runs: runs)
        let controller = CodeController(
            store: InMemoryKeyValueStore(),
            secrets: InMemorySecretStore(),
            http: fixture,
            portainerHTTP: { _ in fixture }
        )
        try? controller.configureGitHub(token: CodeFixtureHTTPClient.githubToken)
        try? controller.configurePortainer(server: CodeFixtureHTTPClient.server, token: CodeFixtureHTTPClient.portainerToken)
        controller.targets = targets
        controller.seed(from: fixture)
        return controller
    }

    /// What `run()` would find on its first pass against the fixture, so a preview has data before
    /// any task runs.
    private func seed(from fixture: CodeFixtureHTTPClient) {
        let now = clock.now
        github = fixture.github
        githubConnection = .ready
        let workflows = fixture.workflows
        workflowCache = workflows.mapValues { (now, $0) }
        candidates = DeployDiscovery.candidates(containers: fixture.containers, login: fixture.github.login, workflows: workflows)
        runCache = fixture.latestRuns
        let needingImages = Set(fixture.containers.filter(DeployDiscovery.needsImage).map(\.imageID))
        imageCache = fixture.images.filter { needingImages.contains($0.key) }
        lastContainers = fixture.containers
        recomputeDeploys()
        deploysCheckedAt = now
        portainerConnection = .ready
    }

    private var githubToken: String? {
        guard let token = (try? secrets.string(for: .githubToken)) ?? nil, !token.isEmpty else { return nil }
        return token
    }

    private var portainerToken: String? {
        guard let token = (try? secrets.string(for: .portainerToken)) ?? nil, !token.isEmpty else { return nil }
        return token
    }

    private var isPortainerConfigured: Bool {
        portainer != nil && portainerToken != nil
    }

    private func resetGitHubState() {
        githubAuthRejected = false
        githubPausedUntil = nil
        githubProblem = nil
        githubFailures = 0
        githubDownSince = nil
        deployLogin = nil
        workflowCache = [:]
        runCache = [:]
    }

    private func resetPortainerState() {
        portainerClient = nil
        portainerAuthRejected = false
        portainerProblem = nil
        deployFailures = 0
        portainerDownSince = nil
    }

    private func githubLoop() async {
        while !Task.isCancelled {
            pendingWakes.remove(.github)
            guard let token = githubToken else {
                githubConnection = .notConfigured
                await sleep(.github, until: clock.now.addingTimeInterval(Self.idleInterval))
                continue
            }
            if githubAuthRejected {
                githubConnection = .authFailed
                await sleep(.github, until: clock.now.addingTimeInterval(Self.idleInterval))
                continue
            }
            if let pausedUntil = githubPausedUntil, pausedUntil > clock.now {
                githubConnection = .failed(since: githubDownSince ?? clock.now, retryAt: pausedUntil)
                await sleep(.github, until: pausedUntil)
                continue
            }
            let generation = githubGeneration
            let result: Result<GitHubSnapshot, any Error>
            do {
                result = .success(try await fetchGitHub(token: token, previous: github))
            } catch {
                result = .failure(error)
            }
            syncCounters()
            if Task.isCancelled { break }
            guard generation == githubGeneration else { continue }
            let next: Date
            switch result {
            case .success(let snapshot):
                github = snapshot
                save(snapshot, forKey: Keys.github)
                githubConnection = .ready
                if githubProblem != .missingPermission("Actions") { githubProblem = nil }
                githubFailures = 0
                githubDownSince = nil
                githubPausedUntil = nil
                next = clock.now.addingTimeInterval(Self.githubInterval)
            case .failure(let error):
                next = githubFailed(error)
            }
            await sleep(.github, until: next)
        }
    }

    private func fetchGitHub(token: String, previous: GitHubSnapshot?) async throws -> GitHubSnapshot {
        let client = githubClient(token: token)
        let viewer = try await client.viewer()
        var latest = previous?.login == viewer.login ? previous?.latestCommit : nil
        do {
            latest = try await client.latestCommit(repositories: viewer.repositories, previous: latest) ?? latest
        } catch GitHubError.unauthorized {
            throw GitHubError.unauthorized
        } catch GitHubError.rateLimited(let until) {
            throw GitHubError.rateLimited(until: until)
        } catch {
            // The calendar is still good; the commit line keeps its last value.
        }
        return GitHubSnapshot(login: viewer.login, calendar: viewer.calendar, latestCommit: latest, fetchedAt: clock.now)
    }

    /// Records a failed GitHub refresh and returns when to try again.
    private func githubFailed(_ error: any Error) -> Date {
        let now = clock.now
        if case GitHubError.unauthorized = error {
            githubAuthRejected = true
            githubProblem = .invalidToken
            githubConnection = .authFailed
            return now.addingTimeInterval(Self.idleInterval)
        }
        let retryAt: Date
        if case GitHubError.rateLimited(let until) = error {
            retryAt = max(until, now.addingTimeInterval(30))
            githubPausedUntil = retryAt
        } else {
            retryAt = now.addingTimeInterval(backoff.delay(attempt: githubFailures))
            githubFailures += 1
        }
        let since = githubDownSince ?? now
        githubDownSince = since
        githubProblem = Self.setupError(error)
        githubConnection = .failed(since: since, retryAt: retryAt)
        return retryAt
    }

    private func deployLoop() async {
        while !Task.isCancelled {
            pendingWakes.remove(.deploys)
            guard let server = portainer, let token = portainerToken else {
                portainerConnection = .notConfigured
                await sleep(.deploys, until: clock.now.addingTimeInterval(Self.idleInterval))
                continue
            }
            if portainerAuthRejected {
                portainerConnection = .authFailed
                await sleep(.deploys, until: clock.now.addingTimeInterval(Self.idleInterval))
                continue
            }
            let generation = deployGeneration
            let result: Result<DeployRefresh, any Error>
            do {
                result = .success(try await fetchDeploys(server: server, token: token, generation: generation))
            } catch {
                result = .failure(error)
            }
            syncCounters()
            if Task.isCancelled { break }
            guard generation == deployGeneration else { continue }
            let next: Date
            switch result {
            case .success(let refresh):
                apply(refresh)
                next = clock.now.addingTimeInterval(Self.deployInterval)
            case .failure(let error):
                next = portainerFailed(error)
            }
            await sleep(.deploys, until: next)
        }
    }

    private struct DeployRefresh {
        let containers: [PortainerContainer]
        /// Nil when GitHub could not be asked, so the last candidates stand.
        let candidates: [DeployTarget]?
    }

    /// Reads the containers, finds the candidates, and fills the run and image caches for the
    /// active targets. Only a Portainer failure fails it; GitHub trouble leaves the caches as
    /// they were.
    private func fetchDeploys(server: PortainerServer, token: String, generation: Int) async throws -> DeployRefresh {
        let portainer = PortainerClient(http: portainerHTTPClient(for: server), server: server, token: token)
        let containers = try await portainer.containers()

        var found: [DeployTarget]?
        if let github = githubAccess() {
            do {
                let login = try await viewerLogin(using: github, generation: generation)
                let owned = DeployDiscovery.ownedContainers(containers, login: login)
                var workflows: [String: [WorkflowFile]] = [:]
                for repository in owned.keys.sorted() {
                    workflows[repository] = try await workflowFiles(for: repository, using: github, generation: generation)
                }
                found = DeployDiscovery.candidates(containers: containers, login: login, workflows: workflows)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                noteGitHubTrouble(error, generation: generation)
            }
        }

        let active = targets ?? found ?? candidates
        for target in active {
            guard let github = githubAccess() else { break }
            do {
                let run = try await github.latestSuccessfulRun(repository: target.repository, workflow: target.workflow)
                try ensureCurrent(generation)
                runCache[RunKey(target)] = run
                if githubProblem == .missingPermission("Actions") { githubProblem = nil }
            } catch GitHubError.notFound {
                try ensureCurrent(generation)
                runCache[RunKey(target)] = nil
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                noteGitHubTrouble(error, generation: generation)
            }
        }

        for target in active {
            guard let container = DeployDiscovery.container(for: target, in: containers),
                  DeployDiscovery.needsImage(container),
                  imageCache[container.imageID] == nil else { continue }
            if let image = try? await portainer.image(id: container.imageID) {
                try ensureCurrent(generation)
                if imageCache.count > 64 { imageCache = [:] }
                imageCache[container.imageID] = image
            }
        }
        return DeployRefresh(containers: containers, candidates: found)
    }

    private func apply(_ refresh: DeployRefresh) {
        lastContainers = refresh.containers
        if let found = refresh.candidates, found != candidates {
            candidates = found
            save(found, forKey: Keys.candidates)
        }
        recomputeDeploys()
        deploysCheckedAt = clock.now
        portainerConnection = .ready
        portainerProblem = nil
        deployFailures = 0
        portainerDownSince = nil
    }

    private func recomputeDeploys() {
        let fresh = DeployDiscovery.statuses(targets: activeTargets, containers: lastContainers, runs: runCache, images: imageCache)
        if fresh != deploys { deploys = fresh }
    }

    /// Records a failed Portainer read and returns when to try again.
    private func portainerFailed(_ error: any Error) -> Date {
        let now = clock.now
        if case PortainerError.unauthorized = error {
            portainerAuthRejected = true
            portainerProblem = .invalidToken
            portainerConnection = .authFailed
            return now.addingTimeInterval(Self.idleInterval)
        }
        let retryAt = now.addingTimeInterval(backoff.delay(attempt: deployFailures))
        deployFailures += 1
        let since = portainerDownSince ?? now
        portainerDownSince = since
        portainerProblem = Self.setupError(error)
        portainerConnection = .failed(since: since, retryAt: retryAt)
        return retryAt
    }

    /// A GitHub client for the deploy check, or nil while there is no usable token or the rate
    /// limit says to wait.
    private func githubAccess() -> GitHubClient? {
        guard let token = githubToken, !githubAuthRejected else { return nil }
        if let pausedUntil = githubPausedUntil, pausedUntil > clock.now { return nil }
        return githubClient(token: token)
    }

    /// Every GitHub or Portainer setting change moves `deployGeneration` on, so a result that
    /// arrives after one belongs to the old settings and must not land in the caches.
    private func ensureCurrent(_ generation: Int) throws {
        guard generation == deployGeneration else { throw CancellationError() }
    }

    private func viewerLogin(using client: GitHubClient, generation: Int) async throws -> String {
        if let login = github?.login ?? deployLogin { return login }
        let login = try await client.login().login
        try ensureCurrent(generation)
        deployLogin = login
        return login
    }

    /// A repository's workflow files, from a cache that lasts an hour. A repository the token
    /// cannot read Actions for has none, asked again on every pass so a permission granted later
    /// is noticed.
    private func workflowFiles(for repository: String, using client: GitHubClient, generation: Int) async throws -> [WorkflowFile] {
        let key = repository.lowercased()
        if let cached = workflowCache[key], clock.now.timeIntervalSince(cached.fetchedAt) < Self.workflowLifetime {
            return cached.files
        }
        do {
            let files = try await client.workflows(repository: repository)
            try ensureCurrent(generation)
            workflowCache[key] = (clock.now, files)
            if githubProblem == .missingPermission("Actions") { githubProblem = nil }
            return files
        } catch GitHubError.forbidden, GitHubError.notFound {
            try ensureCurrent(generation)
            githubProblem = .missingPermission("Actions")
            return []
        } catch GitHubError.unauthorized {
            throw GitHubError.unauthorized
        } catch GitHubError.rateLimited(let until) {
            throw GitHubError.rateLimited(until: until)
        } catch {
            if !(error is CancellationError), let stale = workflowCache[key] { return stale.files }
            throw error
        }
    }

    /// GitHub trouble met during a deploy check: a refused token or a rate limit stops GitHub
    /// requests for both loops; anything else waits for the next pass.
    private func noteGitHubTrouble(_ error: any Error, generation: Int) {
        guard generation == deployGeneration else { return }
        switch error {
        case GitHubError.unauthorized:
            githubAuthRejected = true
            githubProblem = .invalidToken
            githubConnection = .authFailed
        case GitHubError.rateLimited(let until):
            githubPausedUntil = max(githubPausedUntil ?? until, until)
        case GitHubError.forbidden:
            githubProblem = .missingPermission("Actions")
        default:
            break
        }
    }

    private func githubClient(token: String) -> GitHubClient {
        let clock = clock
        return GitHubClient(http: CountingHTTPClient(base: http, counter: githubCounter), token: token, now: { clock.now })
    }

    private func portainerHTTPClient(for server: PortainerServer) -> any HTTPClient {
        if let cached = portainerClient, cached.server == server { return cached.http }
        let client = CountingHTTPClient(base: portainerHTTP(server), counter: portainerCounter)
        portainerClient = (server, client)
        return client
    }

    private func syncCounters() {
        if githubRequestCount != githubCounter.count { githubRequestCount = githubCounter.count }
        if portainerRequestCount != portainerCounter.count { portainerRequestCount = portainerCounter.count }
    }

    private func restartGitHub() {
        githubGeneration += 1
        wake(.github)
    }

    private func restartDeploys() {
        deployGeneration += 1
        wake(.deploys)
    }

    private func sleep(_ loop: Loop, until deadline: Date) async {
        if pendingWakes.remove(loop) != nil { return }
        let clock = clock
        let task = Task { try await clock.sleep(until: deadline) }
        sleepers[loop] = task
        await withTaskCancellationHandler {
            _ = try? await task.value
        } onCancel: {
            task.cancel()
        }
        if sleepers[loop] == task { sleepers[loop] = nil }
    }

    private func wake(_ loop: Loop) {
        if let sleeper = sleepers[loop] {
            sleepers[loop] = nil
            sleeper.cancel()
        } else {
            pendingWakes.insert(loop)
        }
    }

    static func setupError(_ error: any Error) -> CodeSetupError {
        switch error {
        case GitHubError.unauthorized, PortainerError.unauthorized:
            return .invalidToken
        case GitHubError.rateLimited:
            return .unexpectedReply("GitHub rate limit reached")
        case GitHubError.forbidden:
            return .unexpectedReply("HTTP 403")
        case GitHubError.notFound:
            return .unexpectedReply("HTTP 404")
        case GitHubError.status(let code), PortainerError.status(let code):
            return .unexpectedReply("HTTP \(code)")
        case GitHubError.graphQL(let message):
            return .unexpectedReply(message)
        case GitHubError.malformed(let what), PortainerError.malformed(let what):
            return .unexpectedReply("Unreadable \(what)")
        case PortainerError.notFound:
            return .unknownEnvironment
        case PortainerError.forbidden:
            return .missingPermission("Environment")
        case is PortainerCertificateError:
            return .certificateChanged
        case let error as URLError:
            switch error.code {
            case .timedOut: return .timeout
            case .badURL, .unsupportedURL: return .badAddress
            default: return .unreachable
            }
        default:
            return .unreachable
        }
    }

    private func save(_ value: some Encodable, forKey key: String) {
        store.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, from store: any KeyValueStore, key: String) -> T? {
        store.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
