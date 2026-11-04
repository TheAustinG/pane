import Foundation
import Testing
@testable import PaneCore

private let start = CodeSample.start
private let latestCommit = LatestCommit(
    repository: "sample-user/lantern",
    branch: "main",
    sha: CodeSample.latestSHA,
    headline: CodeSample.latestHeadline,
    date: CodeSample.date("2026-11-04T02:12:15Z")
)

@Suite("Code controller", .timeLimit(.minutes(1)))
@MainActor
struct CodeControllerTests {
    @Test func refreshesGitHubAndDeploysOnLaunch() async throws {
        let harness = CodeHarness()
        let controller = harness.controller
        #expect(controller.githubConnection == .loading)
        #expect(controller.portainerConnection == .loading)
        await harness.refreshBoth()

        let github = try #require(controller.github)
        #expect(github.login == "sample-user")
        #expect(github.latestCommit == latestCommit)
        #expect(github.fetchedAt == start)
        #expect(controller.contributionSummary()?.todayCount == 7)
        #expect(controller.contributionSummary()?.streak == 5)

        #expect(controller.candidates == [CodeSample.beacon, CodeSample.ledger])
        #expect(controller.activeTargets == controller.candidates)
        #expect(controller.deploys.map(\.verdict) == [.current, .behind(builtAt: CodeSample.ledgerBuiltAt)])
        #expect(controller.nudges.map(\.target) == [CodeSample.ledger])
        #expect(controller.deploysCheckedAt == start)
        #expect(controller.githubProblem == nil)
        #expect(controller.portainerProblem == nil)

        #expect(harness.clock.deadlines == [start.addingTimeInterval(300), start.addingTimeInterval(600)])
        #expect(controller.githubRequestCount == harness.github.count)
        #expect(controller.portainerRequestCount == 1)
        #expect(harness.portainer.keys == ["/api/endpoints/3/docker/containers/json"])
        #expect(harness.github.count("/repos/sample-user/beacon/actions/workflows/publish.yml/runs") == 1)
        #expect(harness.portainerServers == [CodeSample.server])
        await harness.stop()
    }

    @Test func refreshesOnTheirOwnSchedules() async {
        let harness = CodeHarness()
        await harness.refreshBoth()
        let controller = harness.controller
        let viewerRequests = harness.github.count(FakeHTTP.viewer)

        harness.clock.advance(by: 300)
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(600), count: 2)
        await waitUntil { controller.portainerRequestCount == 2 }
        #expect(harness.github.count(FakeHTTP.viewer) == viewerRequests)

        harness.clock.advance(by: 300)
        await waitUntil { controller.github?.fetchedAt == start.addingTimeInterval(600) }
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(1200), count: 1)
        #expect(harness.github.count(FakeHTTP.viewer) == viewerRequests + 1)
        // Same commit as before: its headline is reused, not fetched again.
        #expect(harness.github.count("/repos/sample-user/lantern/commits/\(CodeSample.latestSHA)") == 1)
        // Workflow lists are cached for an hour.
        #expect(harness.github.count("/repos/sample-user/beacon/actions/workflows") == 1)
        await harness.stop()
    }

    @Test func gitHubFailuresBackOffAndKeepTheLastSnapshot() async {
        let harness = CodeHarness()
        await harness.refreshBoth()
        let controller = harness.controller
        let snapshot = controller.github

        harness.github.set(FakeHTTP.viewer, status: 502)
        controller.refreshNow()
        await waitUntil { controller.githubConnection == .failed(since: start, retryAt: start.addingTimeInterval(60)) }
        #expect(controller.github == snapshot)
        #expect(controller.githubProblem == .unexpectedReply("HTTP 502"))

        await harness.clock.waitForSleeper(until: start.addingTimeInterval(60))
        harness.clock.advance(by: 60)
        await waitUntil { controller.githubConnection == .failed(since: start, retryAt: start.addingTimeInterval(180)) }

        await harness.clock.waitForSleeper(until: start.addingTimeInterval(180))
        harness.github.set(FakeHTTP.viewer, fixture: "github-viewer")
        harness.clock.advance(by: 120)
        await waitUntil { controller.githubConnection == .ready }
        #expect(controller.github?.fetchedAt == start.addingTimeInterval(180))
        #expect(controller.githubProblem == nil)
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(780))
        await harness.stop()
    }

    @Test func backoffIsCappedAtFifteenMinutes() {
        let backoff = CodeController.defaultBackoff
        #expect(backoff.delay(attempt: 0, random: 0) == 60)
        #expect(backoff.delay(attempt: 3, random: 0) == 480)
        #expect(backoff.delay(attempt: 4, random: 0) == 900)
        #expect(backoff.delay(attempt: 30, random: 1) == 900)
    }

    @Test func aRefusedTokenStopsGitHubUntilItChanges() async {
        let harness = CodeHarness()
        harness.github.set(FakeHTTP.viewer, fixture: "github-bad-credentials", status: 401)
        harness.github.set(FakeHTTP.login, fixture: "github-bad-credentials", status: 401)
        let controller = harness.controller
        harness.launch()
        await waitUntil { controller.githubConnection == .authFailed && controller.portainerConnection == .ready }
        #expect(controller.githubProblem == .invalidToken)
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(3600))
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(300))
        let sent = harness.github.count

        for hour in 1...3 {
            harness.clock.advance(by: 3600)
            await harness.clock.waitForSleeper(until: start.addingTimeInterval(Double(hour + 1) * 3600))
            await harness.clock.waitForSleeper(until: start.addingTimeInterval(Double(hour) * 3600 + 300))
        }
        #expect(harness.github.count == sent)
        #expect(controller.githubConnection == .authFailed)
        #expect(controller.portainerRequestCount == 4)

        harness.github.set(FakeHTTP.viewer, fixture: "github-viewer")
        harness.github.set(FakeHTTP.login, fixture: "github-viewer")
        try? controller.configureGitHub(token: "sample-new-token")
        #expect(controller.githubConnection == .loading)
        await waitUntil { controller.githubConnection == .ready && controller.candidates.count == 2 }
        #expect(harness.github.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer sample-new-token")
        await harness.stop()
    }

    @Test func theOldTokensRefusalDoesNotBlockANewToken() async {
        let harness = CodeHarness()
        let controller = harness.controller
        harness.github.set(FakeHTTP.login, fixture: "github-bad-credentials", status: 401)
        harness.github.hold(FakeHTTP.login)
        harness.github.hold(FakeHTTP.viewer)
        harness.launch()
        await harness.github.waitForHeldRequest(FakeHTTP.login)
        await harness.github.waitForHeldRequest(FakeHTTP.viewer)

        harness.github.set(FakeHTTP.login, fixture: "github-viewer")
        try? controller.configureGitHub(token: "sample-new-token")
        harness.github.release(FakeHTTP.login)
        harness.github.release(FakeHTTP.viewer)
        await waitUntil {
            (controller.githubConnection == .ready && controller.candidates.count == 2)
                || controller.githubConnection == .authFailed || controller.githubProblem != nil
        }
        #expect(controller.githubConnection == .ready)
        #expect(controller.candidates.count == 2)
        #expect(controller.githubProblem == nil)
        await harness.stop()
    }

    @Test func aRateLimitWaitsForTheReset() async {
        let harness = CodeHarness()
        let reset = start.addingTimeInterval(1800)
        let headers = ["x-ratelimit-remaining": "0", "x-ratelimit-reset": String(Int(reset.timeIntervalSince1970))]
        harness.github.set(FakeHTTP.viewer, status: 403, json: #"{"message":"API rate limit exceeded"}"#, headers: headers)
        let controller = harness.controller
        harness.launch()
        await waitUntil { controller.githubConnection == .failed(since: start, retryAt: reset) }
        #expect(controller.githubProblem == .unexpectedReply("GitHub rate limit reached"))
        await harness.clock.waitForSleeper(until: reset)
        await harness.stop()
    }

    @Test func graphQLErrorsFailTheRefresh() async {
        let harness = CodeHarness()
        harness.github.set(FakeHTTP.viewer, fixture: "github-graphql-error")
        let controller = harness.controller
        harness.launch()
        await waitUntil { controller.githubConnection == .failed(since: start, retryAt: start.addingTimeInterval(60)) }
        #expect(controller.githubProblem == .unexpectedReply("Field 'nosuchfield' doesn't exist on type 'User'"))
        #expect(controller.github == nil)
        await harness.stop()
    }

    @Test func refreshNowWakesBothLoops() async {
        let harness = CodeHarness()
        await harness.refreshBoth()
        let controller = harness.controller
        let github = controller.githubRequestCount

        controller.refreshNow()
        await waitUntil { controller.portainerRequestCount == 2 && controller.githubRequestCount >= github + 4 }
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(600))
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(300))
        #expect(controller.githubRequestCount == github + 4)
        await harness.stop()
    }

    @Test func settingsPersistAndTokensStayInTheSecretStore() async throws {
        let store = InMemoryKeyValueStore()
        let secrets = InMemorySecretStore()
        let harness = CodeHarness(store: store, secrets: secrets)
        try harness.controller.configurePortainer(server: CodeSample.pinnedServer, token: CodeSample.portainerToken)
        await harness.refreshBoth()
        harness.controller.targets = [CodeSample.beacon]
        harness.controller.nudgeEnabled = false
        await harness.stop()

        let next = CodeController(store: store, secrets: secrets, http: FakeHTTP(), portainerHTTP: { _ in FakeHTTP() })
        #expect(next.github == harness.controller.github)
        #expect(next.github?.latestCommit == latestCommit)
        #expect(next.portainer == CodeSample.pinnedServer)
        #expect(next.portainer?.pinnedCertificateSHA256 == CodeSample.pinnedServer.pinnedCertificateSHA256)
        #expect(next.targets == [CodeSample.beacon])
        #expect(next.nudgeEnabled == false)
        #expect(next.candidates == [CodeSample.beacon, CodeSample.ledger])
        #expect(next.hasGitHubToken)
        #expect(next.hasPortainerToken)
        #expect(next.githubConnection == .loading)
        #expect(next.portainerConnection == .loading)

        for key in CodeController.Keys.all {
            let text = String(decoding: store.data(forKey: key) ?? Data(), as: UTF8.self)
            #expect(!text.isEmpty, "\(key) was not saved")
            #expect(!text.contains(CodeSample.githubToken))
            #expect(!text.contains(CodeSample.portainerToken))
        }
        #expect(try secrets.string(for: .githubToken) == CodeSample.githubToken)
        #expect(try secrets.string(for: .portainerToken) == CodeSample.portainerToken)

        next.targets = nil
        #expect(store.data(forKey: CodeController.Keys.targets) == nil)
    }

    @Test func resetClearsEverythingSaved() async throws {
        let store = InMemoryKeyValueStore()
        let secrets = InMemorySecretStore()
        let harness = CodeHarness(store: store, secrets: secrets)
        await harness.refreshBoth()
        harness.controller.targets = [CodeSample.ledger]
        harness.controller.nudgeEnabled = false
        await harness.stop()

        CodeController.reset(store: store, secrets: secrets)
        for key in CodeController.Keys.all {
            #expect(store.data(forKey: key) == nil)
        }
        #expect(try secrets.string(for: .githubToken) == nil)
        #expect(try secrets.string(for: .portainerToken) == nil)
        let fresh = CodeController(store: store, secrets: secrets, http: FakeHTTP(), portainerHTTP: { _ in FakeHTTP() })
        #expect(fresh.github == nil)
        #expect(fresh.portainer == nil)
        #expect(fresh.targets == nil)
        #expect(fresh.nudgeEnabled)
        #expect(fresh.candidates.isEmpty)
        #expect(fresh.githubConnection == .notConfigured)
        #expect(fresh.portainerConnection == .notConfigured)
    }

    @Test func forgetClearsEachSide() async throws {
        let harness = CodeHarness()
        await harness.refreshBoth()
        let controller = harness.controller

        try controller.forgetGitHub()
        #expect(controller.github == nil)
        #expect(!controller.hasGitHubToken)
        #expect(controller.githubConnection == .notConfigured)
        #expect(harness.store.data(forKey: CodeController.Keys.github) == nil)

        controller.targets = [CodeSample.beacon]
        try controller.forgetPortainer()
        #expect(controller.portainer == nil)
        #expect(controller.targets == nil)
        #expect(controller.candidates.isEmpty)
        #expect(controller.deploys.isEmpty)
        #expect(controller.portainerConnection == .notConfigured)
        #expect(harness.store.data(forKey: CodeController.Keys.portainer) == nil)
        #expect(harness.store.data(forKey: CodeController.Keys.candidates) == nil)
        await harness.stop()
    }

    @Test func aChangedCertificateFailsPortainer() async {
        let portainer = FakeHTTP()
        portainer.fail(with: PortainerCertificateError(observed: String(repeating: "0f", count: 32)))
        let harness = CodeHarness(portainerHTTP: portainer)
        let controller = harness.controller
        harness.launch()
        await waitUntil { controller.portainerConnection == .failed(since: start, retryAt: start.addingTimeInterval(60)) }
        #expect(controller.portainerProblem == .certificateChanged)
        #expect(controller.deploys.isEmpty)
        await harness.stop()
    }

    @Test func aRefusedPortainerKeyStopsTheChecks() async {
        let harness = CodeHarness()
        harness.portainer.set("/api/endpoints/3/docker/containers/json", fixture: "portainer-bad-key", status: 401)
        let controller = harness.controller
        harness.launch()
        await waitUntil { controller.portainerConnection == .authFailed }
        #expect(controller.portainerProblem == .invalidToken)
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(3600), count: 1)
        let sent = harness.portainer.count
        harness.clock.advance(by: 3600)
        await harness.clock.waitForSleeper(until: start.addingTimeInterval(7200), count: 1)
        #expect(harness.portainer.count == sent)
        await harness.stop()
    }

    @Test func missingActionsPermissionLeavesNoCandidates() async {
        let harness = CodeHarness()
        let forbidden = #"{"message":"Resource not accessible by personal access token"}"#
        harness.github.set("/repos/sample-user/beacon/actions/workflows", status: 403, json: forbidden)
        harness.github.set("/repos/sample-user/ledger/actions/workflows", status: 403, json: forbidden)
        await harness.refreshBoth()
        let controller = harness.controller
        #expect(controller.candidates.isEmpty)
        #expect(controller.deploys.isEmpty)
        #expect(controller.githubProblem == .missingPermission("Actions"))
        #expect(controller.githubConnection == .ready)
        #expect(controller.portainerConnection == .ready)

        harness.github.set("/repos/sample-user/beacon/actions/workflows", fixture: "github-workflows")
        harness.github.set("/repos/sample-user/ledger/actions/workflows", fixture: "github-workflows")
        harness.clock.advance(by: CodeController.deployInterval)
        await waitUntil { controller.candidates.count == 2 }
        #expect(controller.githubProblem == nil)
        await harness.stop()
    }

    @Test func targetsAndNudgeSwitches() async {
        let harness = CodeHarness()
        await harness.refreshBoth()
        let controller = harness.controller
        let ledger = controller.deploys[1]
        #expect(controller.nudges == [ledger])

        controller.nudgeEnabled = false
        #expect(controller.nudges.isEmpty)
        controller.nudgeEnabled = true

        controller.debugNudge = true
        #expect(controller.nudges.map(\.target) == [CodeSample.ledger, CodeSample.beacon])
        #expect(controller.nudges.last?.verdict == .behind(builtAt: CodeSample.beaconBuiltAt))
        controller.debugNudge = false
        #expect(controller.nudges.isEmpty)
        controller.debugNudge = nil

        controller.targets = [CodeSample.beacon]
        #expect(controller.deploys.map(\.target) == [CodeSample.beacon])
        #expect(controller.nudges.isEmpty)
        controller.debugNudge = true
        #expect(controller.nudges.map(\.verdict) == [.behind(builtAt: CodeSample.beaconBuiltAt)])
        await harness.stop()
    }

    @Test func debugNudgeWithoutDataUsesThreeHoursAgo() {
        let harness = CodeHarness(configurePortainer: false)
        let controller = harness.controller
        controller.targets = [CodeSample.beacon]
        controller.debugNudge = true
        #expect(controller.nudges.map(\.verdict) == [.behind(builtAt: start.addingTimeInterval(-3 * 3600))])
    }

    @Test func aNewServerRestartsTheChecks() async throws {
        let harness = CodeHarness()
        await harness.refreshBoth()
        let controller = harness.controller
        let other = try #require(PortainerServer(address: "https://portainer.fixture.invalid:9443", environmentID: 4))

        try controller.configurePortainer(server: other, token: CodeSample.portainerToken)
        #expect(controller.deploys.isEmpty)
        #expect(controller.portainerConnection == .loading)
        await waitUntil { controller.portainerConnection == .failed(since: start, retryAt: start.addingTimeInterval(60)) }
        #expect(controller.portainerProblem == .unknownEnvironment)
        #expect(harness.portainerServers == [CodeSample.server, other])
        #expect(harness.portainer.keys.last == "/api/endpoints/4/docker/containers/json")
        await harness.stop()
    }

    @Test func withoutGitHubTheDeployCheckKeepsItsCandidates() async throws {
        let store = InMemoryKeyValueStore()
        let secrets = InMemorySecretStore()
        let first = CodeHarness(store: store, secrets: secrets)
        await first.refreshBoth()
        await first.stop()
        try first.controller.forgetGitHub()

        let harness = CodeHarness(configureGitHub: false, configurePortainer: false, store: store, secrets: secrets)
        harness.launch()
        await waitUntil { harness.controller.portainerConnection == .ready }
        #expect(harness.controller.githubConnection == .notConfigured)
        #expect(harness.controller.candidates == [CodeSample.beacon, CodeSample.ledger])
        #expect(harness.controller.deploys.map(\.verdict) == [.unknown, .unknown])
        #expect(harness.controller.deploys.map { $0.container?.name } == ["beacon-beacon-1", "ledger"])
        #expect(harness.github.count == 0)
        await harness.stop()
    }

    @Test func imageInspectFillsInAMissingRevision() async {
        let harness = CodeHarness()
        let imageID = "sha256:" + String(repeating: "e", count: 64)
        let containers = #"""
        [{"Id":"c1","Names":["/beacon-beacon-1"],"Image":"ghcr.io/sample-user/beacon:latest","ImageID":"\#(imageID)","State":"running","Created":1790400000,
          "Labels":{"org.opencontainers.image.source":"https://github.com/sample-user/beacon"}}]
        """#
        harness.portainer.set("/api/endpoints/3/docker/containers/json", status: 200, json: containers)
        harness.portainer.set("/api/endpoints/3/docker/images/\(imageID)/json", fixture: "portainer-image")
        await harness.refreshBoth()
        let controller = harness.controller
        #expect(controller.deploys.map(\.verdict) == [.current])
        #expect(harness.portainer.keys == ["/api/endpoints/3/docker/containers/json", "/api/endpoints/3/docker/images/\(imageID)/json"])

        controller.refreshNow()
        await waitUntil { controller.portainerRequestCount == 3 }
        #expect(harness.portainer.count("/api/endpoints/3/docker/images/\(imageID)/json") == 1)
        await harness.stop()
    }
}

@Suite("Code preview", .timeLimit(.minutes(1)))
@MainActor
struct CodePreviewTests {
    static let builtAt = CodeSample.date("2026-11-03T15:00:00Z")
    static let snapshot = GitHubSnapshot(
        login: "sample",
        calendar: ContributionCalendar(days: (0..<20).map { offset in
            ContributionDay(day: CalendarDay(year: 2026, month: 10, day: 15).adding(days: offset), count: offset % 3, level: offset % 3)
        }),
        latestCommit: LatestCommit(repository: "sample/kite", branch: "main", sha: "0a1b2c3d4e5f60718293a4b5c6d7e8f901234567", headline: "Sample headline", date: CodeSample.date("2026-11-03T18:00:00Z")),
        fetchedAt: CodeSample.date("2026-11-03T19:00:00Z")
    )
    static let runs = [
        PublishRun(repository: "sample/kite", workflow: "publish.yml", headSHA: "1111111111111111111111111111111111111111", completedAt: builtAt),
        PublishRun(repository: "sample/kite", workflow: "publish.yml", headSHA: "0000000000000000000000000000000000000000", completedAt: builtAt.addingTimeInterval(-86400)),
        PublishRun(repository: "sample/lamp", workflow: "docker.yml", headSHA: "2222222222222222222222222222222222222222", completedAt: builtAt),
        PublishRun(repository: "sample/reel", workflow: "build.yml", headSHA: "3333333333333333333333333333333333333333", completedAt: builtAt),
    ]
    static let containers = [
        PortainerContainer(
            id: "c-kite", name: "kite", image: "ghcr.io/sample/kite:latest", imageID: "sha256:" + String(repeating: "1", count: 64), state: "running",
            created: CodeSample.date("2026-11-01T00:00:00Z"),
            labels: [
                RevisionComparison.sourceLabel: "https://github.com/sample/kite",
                RevisionComparison.revisionLabel: "0000000000000000000000000000000000000000",
            ]
        ),
        PortainerContainer(
            id: "c-lamp", name: "lamp", image: "ghcr.io/sample/lamp:latest", imageID: "sha256:" + String(repeating: "2", count: 64), state: "running",
            created: CodeSample.date("2026-11-03T15:30:00Z"),
            labels: [
                RevisionComparison.sourceLabel: "https://github.com/sample/lamp",
                RevisionComparison.revisionLabel: "2222222",
            ]
        ),
        PortainerContainer(
            id: "c-reel", name: "reel", image: "ghcr.io/sample/reel:latest", imageID: "sha256:" + String(repeating: "3", count: 64), state: "running",
            created: CodeSample.date("2026-10-01T00:00:00Z"),
            labels: [RevisionComparison.sourceLabel: "https://github.com/sample/reel"]
        ),
    ]

    @Test func previewHasDataBeforeItRuns() {
        let controller = CodeController.preview(github: Self.snapshot, containers: Self.containers, runs: Self.runs)
        #expect(controller.github == Self.snapshot)
        #expect(controller.githubConnection == .ready)
        #expect(controller.portainerConnection == .ready)
        #expect(controller.portainer == CodeFixtureHTTPClient.server)
        #expect(controller.candidates.map(\.repository) == ["sample/kite", "sample/lamp", "sample/reel"])
        #expect(controller.candidates.map(\.workflow) == ["publish.yml", "docker.yml", "build.yml"])
        #expect(controller.deploys.map(\.verdict) == [.behind(builtAt: Self.builtAt), .current, .behind(builtAt: Self.builtAt)])
        #expect(controller.nudges.map(\.target.repository) == ["sample/kite", "sample/reel"])
        #expect(controller.contributionSummary() != nil)
    }

    @Test func previewHonoursTargetsAndTheDebugNudge() {
        let lamp = DeployTarget(repository: "sample/lamp", workflow: "docker.yml", containerName: "lamp")
        let controller = CodeController.preview(github: Self.snapshot, containers: Self.containers, runs: Self.runs, targets: [lamp])
        #expect(controller.deploys.map(\.target) == [lamp])
        #expect(controller.nudges.isEmpty)
        controller.debugNudge = true
        #expect(controller.nudges.map(\.verdict) == [.behind(builtAt: Self.builtAt)])
    }

    @Test func runningKeepsTheSeededData() async {
        let controller = CodeController.preview(github: Self.snapshot, containers: Self.containers, runs: Self.runs)
        let deploys = controller.deploys
        let candidates = controller.candidates
        let task = Task { await controller.run() }
        await waitUntil { controller.github?.fetchedAt != Self.snapshot.fetchedAt && controller.portainerRequestCount >= 1 }
        #expect(controller.github?.login == Self.snapshot.login)
        #expect(controller.github?.calendar == Self.snapshot.calendar)
        #expect(controller.github?.latestCommit == Self.snapshot.latestCommit)
        #expect(controller.githubConnection == .ready)
        #expect(controller.portainerConnection == .ready)
        #expect(controller.candidates == candidates)
        #expect(controller.deploys == deploys)
        task.cancel()
        await task.value
    }
}
