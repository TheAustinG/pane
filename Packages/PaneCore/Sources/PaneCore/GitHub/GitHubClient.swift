import Foundation

/// Why a GitHub request failed. Never carries the token.
enum GitHubError: Error, Hashable, Sendable {
    /// 401: the token is wrong, expired or revoked.
    case unauthorized
    /// The primary or secondary rate limit; nothing should be sent before `until`.
    case rateLimited(until: Date)
    /// 403 without a rate limit: the token lacks a permission.
    case forbidden
    case notFound
    case status(Int)
    /// A 200 reply to a GraphQL query that carried an `errors` array.
    case graphQL(String)
    case malformed(String)
}

struct RepositoryPush: Hashable, Sendable {
    let nameWithOwner: String
    let pushedAt: Date?
}

/// What the viewer query returns: the login, the contribution calendar and the recently pushed
/// repositories, in one request.
struct GitHubViewer: Hashable, Sendable {
    let login: String
    let calendar: ContributionCalendar
    let repositories: [RepositoryPush]
}

struct RepositoryActivity: Hashable, Sendable, Decodable {
    let activityType: String
    let ref: String?
    let after: String?
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case activityType = "activity_type"
        case ref, after, timestamp
    }

    /// Activity types that move a branch to a commit someone made.
    static let pushTypes: Set<String> = ["push", "force_push", "pr_merge", "merge_queue_merge", "branch_creation"]

    var isPush: Bool {
        guard Self.pushTypes.contains(activityType), let after, !after.isEmpty else { return false }
        return after.contains { $0 != "0" }
    }

    var branch: String? {
        guard let ref, ref.hasPrefix("refs/heads/") else { return nil }
        return String(ref.dropFirst("refs/heads/".count))
    }

    static func newestPush(in activities: [RepositoryActivity]) -> RepositoryActivity? {
        activities.filter(\.isPush).max { $0.timestamp < $1.timestamp }
    }
}

struct WorkflowFile: Hashable, Sendable, Codable {
    let path: String
    let state: String

    var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    var isActive: Bool { !state.hasPrefix("disabled") }
}

/// Read-only calls to the GitHub API with a fine-grained token (Contents, Metadata and Actions).
struct GitHubClient: Sendable {
    static let apiURL = URL(string: "https://api.github.com")!
    static let requestTimeout: TimeInterval = 20

    let http: any HTTPClient
    let token: String
    var now: @Sendable () -> Date = { .now }

    static let viewerQuery = """
        query { viewer { login contributionsCollection { contributionCalendar { weeks { contributionDays { date contributionCount contributionLevel } } } } \
        repositories(first: 5, orderBy: {field: PUSHED_AT, direction: DESC}, ownerAffiliations: [OWNER]) { nodes { nameWithOwner pushedAt } } } }
        """

    static let loginQuery = """
        query { viewer { login repositories(first: 1, orderBy: {field: PUSHED_AT, direction: DESC}, ownerAffiliations: [OWNER]) { nodes { nameWithOwner pushedAt } } } }
        """

    func viewer() async throws -> GitHubViewer {
        let data = try await graphQL(Self.viewerQuery)
        return try Self.parseViewer(data, now: now())
    }

    /// The login and the most recently pushed repository, for the setup test and deploy discovery.
    func login() async throws -> (login: String, repositories: [RepositoryPush]) {
        let data = try await graphQL(Self.loginQuery)
        let viewer = try Self.parseViewer(data, now: now())
        return (viewer.login, viewer.repositories)
    }

    func activity(repository: String) async throws -> [RepositoryActivity] {
        let data = try await get(try Self.repoPath(repository, "activity"), query: [URLQueryItem(name: "per_page", value: "10")])
        return try Self.decode([RepositoryActivity].self, from: data)
    }

    /// The commit's message headline. `per_page=1` trims the file list, which otherwise runs to
    /// hundreds of kilobytes on a large merge.
    func commitHeadline(repository: String, sha: String) async throws -> (sha: String, headline: String) {
        let data = try await get(try Self.repoPath(repository, "commits", sha), query: [URLQueryItem(name: "per_page", value: "1")])
        return try Self.parseCommit(data)
    }

    func workflows(repository: String) async throws -> [WorkflowFile] {
        let data = try await get(try Self.repoPath(repository, "actions", "workflows"), query: [URLQueryItem(name: "per_page", value: "100")])
        return try Self.parseWorkflows(data)
    }

    func latestSuccessfulRun(repository: String, workflow: String) async throws -> PublishRun? {
        let path = try Self.repoPath(repository, "actions", "workflows", workflow, "runs")
        let data = try await get(path, query: [URLQueryItem(name: "status", value: "success"), URLQueryItem(name: "per_page", value: "1")])
        return try Self.parseRun(data, repository: repository, workflow: workflow)
    }

    /// The newest commit pushed to any of `repositories`. Repositories are read newest push first
    /// and the walk stops once the next one was last pushed before the best commit found, so a
    /// quiet day costs one activity request.
    func latestCommit(repositories: [RepositoryPush], previous: LatestCommit?) async throws -> LatestCommit? {
        let ordered = repositories.sorted { ($0.pushedAt ?? .distantPast) > ($1.pushedAt ?? .distantPast) }
        var best: (repository: String, push: RepositoryActivity)?
        for repository in ordered {
            if let best, let pushedAt = repository.pushedAt, pushedAt <= best.push.timestamp { break }
            let activities: [RepositoryActivity]
            do {
                activities = try await activity(repository: repository.nameWithOwner)
            } catch GitHubError.notFound, GitHubError.forbidden {
                continue
            }
            guard let push = RepositoryActivity.newestPush(in: activities) else { continue }
            if let current = best, push.timestamp <= current.push.timestamp { continue }
            best = (repository.nameWithOwner, push)
        }
        guard let best, let sha = best.push.after else { return nil }
        if let previous, previous.repository == best.repository, previous.sha == sha {
            return LatestCommit(repository: best.repository, branch: best.push.branch, sha: sha, headline: previous.headline, date: best.push.timestamp)
        }
        let commit = try await commitHeadline(repository: best.repository, sha: sha)
        return LatestCommit(repository: best.repository, branch: best.push.branch, sha: commit.sha, headline: commit.headline, date: best.push.timestamp)
    }

    func graphQL(_ query: String) async throws -> Data {
        var request = baseRequest(Self.apiURL.appending(path: "graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["query": query])
        let (data, response) = try await http.data(for: request)
        try Self.check(response, now: now())
        try Self.checkGraphQLErrors(data, response: response, now: now())
        return data
    }

    func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: Self.apiURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw GitHubError.malformed("bad path") }
        let (data, response) = try await http.data(for: baseRequest(url))
        try Self.check(response, now: now())
        return data
    }

    private func baseRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Pane", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }

    /// `/repos/owner/name/...`, refusing anything that is not a plain `owner/name` so a container
    /// label can never steer a request elsewhere.
    static func repoPath(_ repository: String, _ rest: String...) throws -> String {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy(isPathSegment), rest.allSatisfy(isPathSegment) else {
            throw GitHubError.malformed("bad repository")
        }
        return "/" + (["repos"] + parts + rest).joined(separator: "/")
    }

    static func isPathSegment(_ text: String) -> Bool {
        guard !text.isEmpty, text != ".", text != ".." else { return false }
        return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }

    static func check(_ response: HTTPURLResponse, now: Date) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw GitHubError.unauthorized
        case 403, 429:
            if let until = rateLimitReset(response, now: now) { throw GitHubError.rateLimited(until: until) }
            if response.statusCode == 429 { throw GitHubError.rateLimited(until: now.addingTimeInterval(60)) }
            throw GitHubError.forbidden
        case 404:
            throw GitHubError.notFound
        default:
            throw GitHubError.status(response.statusCode)
        }
    }

    /// When a rate-limited reply says to try again: the primary limit's reset time when nothing is
    /// left, or `retry-after` for the secondary limit.
    static func rateLimitReset(_ response: HTTPURLResponse, now: Date) -> Date? {
        if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0",
           let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init) {
            return Date(timeIntervalSince1970: reset)
        }
        if let seconds = response.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init) {
            return now.addingTimeInterval(seconds)
        }
        return nil
    }

    private struct GraphQLErrors: Decodable {
        struct Item: Decodable {
            let message: String?
            let type: String?
        }

        let errors: [Item]?
    }

    static func checkGraphQLErrors(_ data: Data, response: HTTPURLResponse, now: Date) throws {
        guard let errors = (try? JSONDecoder().decode(GraphQLErrors.self, from: data))?.errors, !errors.isEmpty else { return }
        if errors.contains(where: { $0.type == "RATE_LIMITED" }) {
            throw GitHubError.rateLimited(until: rateLimitReset(response, now: now) ?? now.addingTimeInterval(60))
        }
        throw GitHubError.graphQL(errors.compactMap(\.message).first ?? "GraphQL error")
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = CodeDate.decodingStrategy
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw GitHubError.malformed(String(describing: T.self))
        }
    }

    private struct ViewerReply: Decodable {
        struct Data: Decodable { let viewer: Viewer }
        struct Viewer: Decodable {
            let login: String
            let contributionsCollection: Collection?
            let repositories: Repositories?
        }
        struct Collection: Decodable { let contributionCalendar: Calendar }
        struct Calendar: Decodable { let weeks: [Week] }
        struct Week: Decodable { let contributionDays: [Day] }
        struct Day: Decodable {
            let date: String
            let contributionCount: Int
            let contributionLevel: String?
        }
        struct Repositories: Decodable { let nodes: [Node?] }
        struct Node: Decodable {
            let nameWithOwner: String
            let pushedAt: String?
        }

        let data: Data?
    }

    static func parseViewer(_ data: Data, now: Date) throws -> GitHubViewer {
        guard let viewer = try decode(ViewerReply.self, from: data).data?.viewer else {
            throw GitHubError.malformed("viewer")
        }
        let days = (viewer.contributionsCollection?.contributionCalendar.weeks ?? [])
            .flatMap(\.contributionDays)
            .compactMap { day -> ContributionDay? in
                guard let calendarDay = CalendarDay(string: day.date) else { return nil }
                return ContributionDay(day: calendarDay, count: max(day.contributionCount, 0), level: level(day.contributionLevel))
            }
            .sorted { $0.day < $1.day }
        let repositories = (viewer.repositories?.nodes ?? []).compactMap { node in
            node.map { RepositoryPush(nameWithOwner: $0.nameWithOwner, pushedAt: $0.pushedAt.flatMap(CodeDate.parse)) }
        }
        return GitHubViewer(login: viewer.login, calendar: ContributionCalendar(days: days), repositories: repositories)
    }

    static func level(_ name: String?) -> Int {
        switch name {
        case "FIRST_QUARTILE": 1
        case "SECOND_QUARTILE": 2
        case "THIRD_QUARTILE": 3
        case "FOURTH_QUARTILE": 4
        default: 0
        }
    }

    private struct CommitReply: Decodable {
        struct Commit: Decodable { let message: String }
        let sha: String
        let commit: Commit
    }

    static func parseCommit(_ data: Data) throws -> (sha: String, headline: String) {
        let reply = try decode(CommitReply.self, from: data)
        let headline = reply.commit.message
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return (reply.sha, headline)
    }

    private struct WorkflowsReply: Decodable {
        struct Workflow: Decodable {
            let path: String
            let state: String?
        }
        let workflows: [Workflow]
    }

    static func parseWorkflows(_ data: Data) throws -> [WorkflowFile] {
        try decode(WorkflowsReply.self, from: data).workflows.map { WorkflowFile(path: $0.path, state: $0.state ?? "active") }
    }

    private struct RunsReply: Decodable {
        struct Run: Decodable {
            let headSHA: String
            let updatedAt: Date
            let conclusion: String?

            enum CodingKeys: String, CodingKey {
                case headSHA = "head_sha"
                case updatedAt = "updated_at"
                case conclusion
            }
        }

        let workflowRuns: [Run]

        enum CodingKeys: String, CodingKey {
            case workflowRuns = "workflow_runs"
        }
    }

    static func parseRun(_ data: Data, repository: String, workflow: String) throws -> PublishRun? {
        let runs = try decode(RunsReply.self, from: data).workflowRuns
        guard let run = runs.first(where: { $0.conclusion == nil || $0.conclusion == "success" }) else { return nil }
        return PublishRun(repository: repository, workflow: workflow, headSHA: run.headSHA, completedAt: run.updatedAt)
    }
}
