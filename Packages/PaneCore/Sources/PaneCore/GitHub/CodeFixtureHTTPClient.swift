import Foundation

/// Answers GitHub and Portainer requests with JSON shaped like the real replies, built from a
/// snapshot, containers and runs, so a preview controller exercises the real decoding.
struct CodeFixtureHTTPClient: HTTPClient {
    static let githubToken = "fixture-github-token"
    static let portainerToken = "fixture-portainer-token"
    static let server = PortainerServer(address: "https://fixture.invalid", environmentID: 1)!
    static let portainerVersion = "2.45.1"

    let github: GitHubSnapshot
    let containers: [PortainerContainer]
    let runs: [PublishRun]

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        respond(to: request)
    }

    /// Each repository's workflow files: one per workflow its runs name.
    var workflows: [String: [WorkflowFile]] {
        var byRepository: [String: (repository: String, files: Set<String>)] = [:]
        for run in runs {
            byRepository[run.repository.lowercased(), default: (run.repository, [])].files.insert(run.workflow)
        }
        return Dictionary(uniqueKeysWithValues: byRepository.values.map { entry in
            (entry.repository, entry.files.sorted().map { WorkflowFile(path: ".github/workflows/\($0)", state: "active") })
        })
    }

    /// The newest run for each repository and workflow.
    var latestRuns: [RunKey: PublishRun] {
        Dictionary(runs.map { (RunKey(repository: $0.repository, workflow: $0.workflow), $0) }) { first, second in
            first.completedAt >= second.completedAt ? first : second
        }
    }

    /// Image inspect for each container: its labels, created at its created label or else when the
    /// container was created.
    var images: [String: PortainerImage] {
        Dictionary(containers.map { container in
            let created = container.labels[RevisionComparison.createdLabel].flatMap(CodeDate.parse) ?? container.created
            return (container.imageID, PortainerImage(created: created, labels: container.labels))
        }) { first, _ in first }
    }

    func respond(to request: URLRequest) -> (Data, HTTPURLResponse) {
        guard let url = request.url else { return reply(400, ["message": "Bad request"], url: URL(string: "https://fixture.invalid")!) }
        let path = url.path.split(separator: "/").map(String.init)
        if url.host() == GitHubClient.apiURL.host() {
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.githubToken)" else {
                return reply(401, ["message": "Bad credentials"], url: url)
            }
            return github(path: path, request: request, url: url)
        }
        guard request.value(forHTTPHeaderField: "X-API-Key") == Self.portainerToken else {
            return reply(401, ["message": "Invalid JWT token", "details": "Unauthorized"], url: url)
        }
        return portainer(path: path, url: url)
    }

    private func github(path: [String], request: URLRequest, url: URL) -> (Data, HTTPURLResponse) {
        if path == ["graphql"] {
            return reply(200, viewerBody(full: request.httpBody.map { String(decoding: $0, as: UTF8.self) }?.contains("contributionsCollection") ?? false), url: url)
        }
        guard path.count >= 4, path[0] == "repos" else { return notFound(url) }
        let repository = "\(path[1])/\(path[2])"
        switch Array(path.dropFirst(3)) {
        case ["activity"]:
            return reply(200, activityBody(repository), url: url)
        case let rest where rest.count == 2 && rest[0] == "commits":
            guard let commit = github.latestCommit, commit.sha == rest[1] else { return notFound(url) }
            return reply(200, ["sha": commit.sha, "commit": ["message": commit.headline]], url: url)
        case ["actions", "workflows"]:
            let files = workflows.first { $0.key.caseInsensitiveCompare(repository) == .orderedSame }?.value ?? []
            let list = files.map { ["path": $0.path, "state": $0.state, "name": $0.fileName] }
            return reply(200, ["total_count": list.count, "workflows": list], url: url)
        case let rest where rest.count == 4 && rest[0] == "actions" && rest[1] == "workflows" && rest[3] == "runs":
            let run = latestRuns[RunKey(repository: repository, workflow: rest[2])]
            let list: [[String: Any]] = run.map { [[
                "head_sha": $0.headSHA,
                "updated_at": CodeDate.string($0.completedAt),
                "status": "completed",
                "conclusion": "success",
                "path": ".github/workflows/\($0.workflow)",
            ]] } ?? []
            return reply(200, ["total_count": list.count, "workflow_runs": list], url: url)
        default:
            return notFound(url)
        }
    }

    private func viewerBody(full: Bool) -> [String: Any] {
        var viewer: [String: Any] = ["login": github.login]
        let nodes: [[String: Any]] = github.latestCommit.map {
            [["nameWithOwner": $0.repository, "pushedAt": CodeDate.string($0.date)]]
        } ?? []
        viewer["repositories"] = ["nodes": nodes]
        if full {
            viewer["contributionsCollection"] = ["contributionCalendar": ["weeks": weeks()]]
        }
        return ["data": ["viewer": viewer]]
    }

    /// The calendar's days in Sunday-first weeks, as GitHub groups them.
    private func weeks() -> [[String: Any]] {
        var weeks: [[[String: Any]]] = []
        for day in github.calendar.days.sorted(by: { $0.day < $1.day }) {
            let entry: [String: Any] = [
                "date": day.day.description,
                "contributionCount": day.count,
                "contributionLevel": Self.levelNames[min(max(day.level, 0), 4)],
            ]
            if day.day.weekday == 1 || weeks.isEmpty {
                weeks.append([entry])
            } else {
                weeks[weeks.count - 1].append(entry)
            }
        }
        return weeks.map { ["contributionDays": $0] }
    }

    private static let levelNames = ["NONE", "FIRST_QUARTILE", "SECOND_QUARTILE", "THIRD_QUARTILE", "FOURTH_QUARTILE"]

    private func activityBody(_ repository: String) -> [[String: Any]] {
        guard let commit = github.latestCommit, commit.repository.caseInsensitiveCompare(repository) == .orderedSame else { return [] }
        var entry: [String: Any] = [
            "activity_type": "push",
            "before": String(repeating: "0", count: 40),
            "after": commit.sha,
            "timestamp": CodeDate.string(commit.date),
        ]
        if let branch = commit.branch { entry["ref"] = "refs/heads/\(branch)" }
        return [entry]
    }

    private func portainer(path: [String], url: URL) -> (Data, HTTPURLResponse) {
        if path == ["api", "system", "status"] {
            return reply(200, ["Version": Self.portainerVersion], url: url)
        }
        let environment = ["api", "endpoints", String(Self.server.environmentID), "docker"]
        guard path.count >= 4, path[0] == "api", path[1] == "endpoints" else { return notFound(url) }
        guard Array(path.prefix(4)) == environment else {
            return reply(404, ["message": "Unable to find an environment with the specified identifier inside the database"], url: url)
        }
        switch Array(path.dropFirst(4)) {
        case ["containers", "json"]:
            return reply(200, containers.map(containerBody), url: url)
        case let rest where rest.count == 3 && rest[0] == "images" && rest[2] == "json":
            guard let container = containers.first(where: { $0.imageID == rest[1] }), let image = images[container.imageID] else {
                return notFound(url)
            }
            var body: [String: Any] = ["Id": container.imageID, "Config": ["Labels": image.labels]]
            if let created = image.created { body["Created"] = CodeDate.string(created) }
            return reply(200, body, url: url)
        default:
            return notFound(url)
        }
    }

    private func containerBody(_ container: PortainerContainer) -> [String: Any] {
        [
            "Id": container.id,
            "Names": ["/\(container.name)"],
            "Image": container.image,
            "ImageID": container.imageID,
            "State": container.state,
            "Created": container.created.timeIntervalSince1970,
            "Labels": container.labels,
        ]
    }

    private func notFound(_ url: URL) -> (Data, HTTPURLResponse) {
        reply(404, ["message": "Not Found"], url: url)
    }

    private func reply(_ status: Int, _ body: Any, url: URL) -> (Data, HTTPURLResponse) {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (data, response)
    }
}
