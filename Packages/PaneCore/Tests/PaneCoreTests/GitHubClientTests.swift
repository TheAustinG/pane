import Foundation
import Testing
@testable import PaneCore

private let now = CodeSample.start

private func client(_ http: FakeHTTP) -> GitHubClient {
    GitHubClient(http: http, token: CodeSample.githubToken, now: { now })
}

private func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://api.github.com/graphql")!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
}

private func activity(_ type: String, after: String?, at timestamp: String, ref: String? = "refs/heads/main") -> RepositoryActivity {
    RepositoryActivity(activityType: type, ref: ref, after: after, timestamp: CodeSample.date(timestamp))
}

private let zeros = String(repeating: "0", count: 40)

@Suite("GitHub client")
struct GitHubClientTests {
    @Test func decodesTheViewerQuery() throws {
        let viewer = try GitHubClient.parseViewer(CodeSample.data("github-viewer"), now: now)
        #expect(viewer.login == "sample-user")
        #expect(viewer.calendar.days.count == 367)
        #expect(viewer.calendar.days.first == ContributionDay(day: CalendarDay(year: 2025, month: 11, day: 2), count: 0, level: 0))
        #expect(viewer.calendar.days.last == ContributionDay(day: CalendarDay(year: 2026, month: 11, day: 3), count: 7, level: 1))
        #expect(viewer.calendar.days.map(\.day) == viewer.calendar.days.map(\.day).sorted())
        #expect(viewer.repositories.count == 5)
        #expect(viewer.repositories.first == RepositoryPush(nameWithOwner: "sample-user/lantern", pushedAt: CodeSample.date("2026-11-04T02:12:15Z")))
    }

    @Test(arguments: [
        ("NONE", 0), ("FIRST_QUARTILE", 1), ("SECOND_QUARTILE", 2), ("THIRD_QUARTILE", 3), ("FOURTH_QUARTILE", 4), ("NEW_LEVEL", 0),
    ])
    func mapsContributionLevels(name: String, level: Int) {
        #expect(GitHubClient.level(name) == level)
    }

    @Test func picksTheNewestPushFromRecordedActivity() throws {
        let activities = try GitHubClient.decode([RepositoryActivity].self, from: CodeSample.data("github-activity"))
        #expect(activities.count == 10)
        let push = try #require(RepositoryActivity.newestPush(in: activities))
        #expect(push.activityType == "pr_merge")
        #expect(push.after == CodeSample.latestSHA)
        #expect(push.branch == "main")
        #expect(push.timestamp == CodeSample.date("2026-11-04T02:12:15Z"))
    }

    @Test func skipsABranchDeletionOnTop() throws {
        let activities = try GitHubClient.decode([RepositoryActivity].self, from: CodeSample.data("github-activity-deletion-first"))
        #expect(activities.first?.activityType == "branch_deletion")
        let push = try #require(RepositoryActivity.newestPush(in: activities))
        #expect(push.activityType == "pr_merge")
        #expect(push.branch == "main")
        #expect(push.timestamp == CodeSample.date("2026-11-01T23:22:30Z"))
    }

    @Test func pushLikeActivityRules() {
        let sha = String(repeating: "a", count: 40)
        #expect(activity("push", after: sha, at: "2026-11-01T00:00:00Z").isPush)
        #expect(activity("force_push", after: sha, at: "2026-11-01T00:00:00Z").isPush)
        #expect(activity("merge_queue_merge", after: sha, at: "2026-11-01T00:00:00Z").isPush)
        #expect(activity("branch_creation", after: sha, at: "2026-11-01T00:00:00Z", ref: "refs/heads/topic").branch == "topic")
        #expect(!activity("branch_deletion", after: zeros, at: "2026-11-01T00:00:00Z").isPush)
        #expect(!activity("push", after: zeros, at: "2026-11-01T00:00:00Z").isPush)
        #expect(!activity("push", after: nil, at: "2026-11-01T00:00:00Z").isPush)
        #expect(!activity("label_added", after: sha, at: "2026-11-01T00:00:00Z").isPush)
        #expect(activity("push", after: sha, at: "2026-11-01T00:00:00Z", ref: "refs/tags/v1").branch == nil)
    }

    @Test func decodesCommitWorkflowsAndRuns() throws {
        let commit = try GitHubClient.parseCommit(CodeSample.data("github-commit"))
        #expect(commit.sha == CodeSample.latestSHA)
        #expect(commit.headline == CodeSample.latestHeadline)

        let workflows = try GitHubClient.parseWorkflows(CodeSample.data("github-workflows"))
        #expect(workflows.map(\.fileName) == ["ci.yml", "publish.yml"])
        #expect(workflows.allSatisfy { $0.isActive })

        let run = try #require(try GitHubClient.parseRun(CodeSample.data("github-runs-beacon"), repository: "sample-user/beacon", workflow: "publish.yml"))
        #expect(run.repository == "sample-user/beacon")
        #expect(run.workflow == "publish.yml")
        #expect(run.headSHA.hasPrefix("6ad3d84"))
        #expect(run.headSHA.count == 40)
        #expect(run.completedAt == CodeSample.beaconBuiltAt)

        let none = try GitHubClient.parseRun(Data(#"{"total_count":0,"workflow_runs":[]}"#.utf8), repository: "a/b", workflow: "publish.yml")
        #expect(none == nil)
        #expect(throws: GitHubError.malformed("RunsReply")) {
            try GitHubClient.parseRun(Data("[]".utf8), repository: "a/b", workflow: "publish.yml")
        }
    }

    @Test func statusCodes() {
        let reset = Date(timeIntervalSince1970: 1_793_761_510)
        #expect(throws: Never.self) { try GitHubClient.check(response(200), now: now) }
        #expect(throws: GitHubError.unauthorized) { try GitHubClient.check(response(401), now: now) }
        #expect(throws: GitHubError.rateLimited(until: reset)) {
            try GitHubClient.check(response(403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1793761510"]), now: now)
        }
        #expect(throws: GitHubError.rateLimited(until: now.addingTimeInterval(90))) {
            try GitHubClient.check(response(403, ["Retry-After": "90"]), now: now)
        }
        #expect(throws: GitHubError.rateLimited(until: now.addingTimeInterval(60))) {
            try GitHubClient.check(response(429), now: now)
        }
        #expect(throws: GitHubError.forbidden) {
            try GitHubClient.check(response(403, ["X-RateLimit-Remaining": "4990"]), now: now)
        }
        #expect(throws: GitHubError.notFound) { try GitHubClient.check(response(404), now: now) }
        #expect(throws: GitHubError.status(502)) { try GitHubClient.check(response(502), now: now) }
    }

    @Test func sendsTheTokenAndApiVersion() async throws {
        let http = FakeHTTP()
        CodeSample.routes(http)
        _ = try await client(http).viewer()
        _ = try await client(http).activity(repository: "sample-user/lantern")
        let graphQL = try #require(http.requests.first)
        #expect(graphQL.httpMethod == "POST")
        #expect(graphQL.url?.absoluteString == "https://api.github.com/graphql")
        #expect(graphQL.value(forHTTPHeaderField: "Authorization") == "Bearer \(CodeSample.githubToken)")
        #expect(graphQL.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(graphQL.value(forHTTPHeaderField: "User-Agent") == "Pane")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(graphQL.httpBody))
        #expect(body["query"]?.contains("contributionLevel") == true)
        #expect(body["query"]?.contains("ownerAffiliations: [OWNER]") == true)
        let rest = http.requests[1]
        #expect(rest.httpMethod == "GET")
        #expect(rest.url?.absoluteString == "https://api.github.com/repos/sample-user/lantern/activity?per_page=10")
        #expect(rest.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    }

    @Test func badCredentialsAreUnauthorized() async {
        let http = FakeHTTP()
        http.set(FakeHTTP.viewer, fixture: "github-bad-credentials", status: 401)
        await #expect(throws: GitHubError.unauthorized) { try await client(http).viewer() }
    }

    @Test func graphQLErrorsInAnOKReplyFail() async {
        let http = FakeHTTP()
        http.set(FakeHTTP.viewer, fixture: "github-graphql-error")
        await #expect(throws: GitHubError.graphQL("Field 'nosuchfield' doesn't exist on type 'User'")) { try await client(http).viewer() }

        http.set(FakeHTTP.viewer, status: 200, json: #"{"data":null,"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#,
                 headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1793761510"])
        await #expect(throws: GitHubError.rateLimited(until: Date(timeIntervalSince1970: 1_793_761_510))) { try await client(http).viewer() }
    }

    @Test func latestCommitReadsOnlyTheNewestRepositoryOnAQuietDay() async throws {
        let http = FakeHTTP()
        CodeSample.routes(http)
        let viewer = try GitHubClient.parseViewer(CodeSample.data("github-viewer"), now: now)
        let latest = try await client(http).latestCommit(repositories: viewer.repositories, previous: nil)
        #expect(latest == LatestCommit(
            repository: "sample-user/lantern",
            branch: "main",
            sha: CodeSample.latestSHA,
            headline: CodeSample.latestHeadline,
            date: CodeSample.date("2026-11-04T02:12:15Z")
        ))
        #expect(http.keys == ["/repos/sample-user/lantern/activity", "/repos/sample-user/lantern/commits/\(CodeSample.latestSHA)"])
        #expect(http.requests.last?.url?.query == "per_page=1")
    }

    @Test func latestCommitKeepsTheHeadlineForTheSameCommit() async throws {
        let http = FakeHTTP()
        CodeSample.routes(http)
        let previous = LatestCommit(repository: "sample-user/lantern", branch: "main", sha: CodeSample.latestSHA, headline: "Kept", date: now)
        let repositories = [RepositoryPush(nameWithOwner: "sample-user/lantern", pushedAt: CodeSample.date("2026-11-04T02:12:15Z"))]
        let latest = try await client(http).latestCommit(repositories: repositories, previous: previous)
        #expect(latest?.headline == "Kept")
        #expect(latest?.date == CodeSample.date("2026-11-04T02:12:15Z"))
        #expect(http.keys == ["/repos/sample-user/lantern/activity"])
    }

    @Test func latestCommitLooksPastARepositoryWhoseLastPushWasADeletion() async throws {
        let http = FakeHTTP()
        http.set("/repos/sample-user/harbor-pull/activity", fixture: "github-activity-deletion-first")
        let newer = #"[{"activity_type":"push","ref":"refs/heads/trunk","after":"\#(String(repeating: "b", count: 40))","timestamp":"2026-11-01T23:22:35Z"}]"#
        http.set("/repos/sample-user/kite-league/activity", status: 200, json: newer)
        http.set("/repos/sample-user/kite-league/commits/\(String(repeating: "b", count: 40))", status: 200,
                 json: #"{"sha":"\#(String(repeating: "b", count: 40))","commit":{"message":"Tune the kite\n\nLonger body"}}"#)
        let repositories = [
            RepositoryPush(nameWithOwner: "sample-user/harbor-pull", pushedAt: CodeSample.date("2026-11-01T23:22:39Z")),
            RepositoryPush(nameWithOwner: "sample-user/kite-league", pushedAt: CodeSample.date("2026-11-01T23:22:35Z")),
            RepositoryPush(nameWithOwner: "sample-user/orchard-ops", pushedAt: CodeSample.date("2026-10-22T05:18:34Z")),
        ]
        let latest = try await client(http).latestCommit(repositories: repositories, previous: nil)
        #expect(latest?.repository == "sample-user/kite-league")
        #expect(latest?.branch == "trunk")
        #expect(latest?.headline == "Tune the kite")
        #expect(!http.keys.contains("/repos/sample-user/orchard-ops/activity"))
    }

    @Test func latestCommitSkipsAnUnreadableRepository() async throws {
        let http = FakeHTTP()
        CodeSample.routes(http)
        http.set("/repos/sample-user/hidden/activity", status: 404)
        let repositories = [
            RepositoryPush(nameWithOwner: "sample-user/hidden", pushedAt: CodeSample.date("2026-11-04T03:00:00Z")),
            RepositoryPush(nameWithOwner: "sample-user/lantern", pushedAt: CodeSample.date("2026-11-04T02:12:15Z")),
        ]
        let latest = try await client(http).latestCommit(repositories: repositories, previous: nil)
        #expect(latest?.repository == "sample-user/lantern")

        http.set("/repos/sample-user/hidden/activity", status: 401)
        await #expect(throws: GitHubError.unauthorized) {
            try await client(http).latestCommit(repositories: repositories, previous: nil)
        }
        #expect(try await client(http).latestCommit(repositories: [], previous: nil) == nil)
    }

    @Test func repositoryPathsRefuseAnythingButOwnerAndName() throws {
        #expect(try GitHubClient.repoPath("sample-user/beacon", "actions", "workflows", "publish.yml", "runs")
            == "/repos/sample-user/beacon/actions/workflows/publish.yml/runs")
        for bad in ["sample-user", "a/b/c", "../b", "a/..", "a/b c", "a/b?x=1", "/b", "a/", "a/b%2F"] {
            #expect(throws: GitHubError.malformed("bad repository")) { try GitHubClient.repoPath(bad) }
        }
        #expect(throws: GitHubError.malformed("bad repository")) { try GitHubClient.repoPath("a/b", "..") }
    }
}

@Suite("GitHub setup test")
struct GitHubSetupTests {
    @Test func returnsTheLogin() async {
        let http = FakeHTTP()
        CodeSample.routes(http)
        http.set("/repos/sample-user/lantern/actions/workflows", fixture: "github-workflows")
        let result = await CodeController.testGitHub(token: "  \(CodeSample.githubToken)\n", http: http)
        #expect(result == .success("sample-user"))
        #expect(http.keys == [FakeHTTP.login, "/repos/sample-user/lantern/actions/workflows"])
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(CodeSample.githubToken)")
    }

    @Test func aRefusedTokenIsInvalid() async {
        let http = FakeHTTP()
        http.set(FakeHTTP.login, fixture: "github-bad-credentials", status: 401)
        #expect(await CodeController.testGitHub(token: "wrong", http: http) == .failure(.invalidToken))
    }

    @Test func anEmptyTokenIsNeverSent() async {
        let http = FakeHTTP()
        #expect(await CodeController.testGitHub(token: " \n", http: http) == .failure(.invalidToken))
        #expect(http.count == 0)
    }

    @Test(arguments: [403, 404])
    func noActionsAccessIsAMissingPermission(status: Int) async {
        let http = FakeHTTP()
        CodeSample.routes(http)
        http.set("/repos/sample-user/lantern/actions/workflows", status: status,
                 json: #"{"message":"Resource not accessible by personal access token"}"#)
        #expect(await CodeController.testGitHub(token: CodeSample.githubToken, http: http) == .failure(.missingPermission("Actions")))
    }

    @Test func networkFailures() async {
        let http = FakeHTTP()
        http.fail(with: URLError(.notConnectedToInternet))
        #expect(await CodeController.testGitHub(token: CodeSample.githubToken, http: http) == .failure(.unreachable))
        http.fail(with: URLError(.timedOut))
        #expect(await CodeController.testGitHub(token: CodeSample.githubToken, http: http) == .failure(.timeout))
    }

    @Test func graphQLErrorsAreUnexpected() async {
        let http = FakeHTTP()
        http.set(FakeHTTP.login, fixture: "github-graphql-error")
        #expect(await CodeController.testGitHub(token: CodeSample.githubToken, http: http)
            == .failure(.unexpectedReply("Field 'nosuchfield' doesn't exist on type 'User'")))
    }
}
