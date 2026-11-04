import Foundation

/// Whether a running container is behind its repository's latest successful publish run.
public enum RevisionComparison {
    public static let revisionLabel = "org.opencontainers.image.revision"
    public static let createdLabel = "org.opencontainers.image.created"
    public static let sourceLabel = "org.opencontainers.image.source"

    /// A run's own image is built while the run is going, so without a revision an image created up
    /// to this long before the run finished still counts as that run's.
    public static let buildWindow: TimeInterval = 10 * 60
    /// With a different revision, an image created more than this long after the run finished was
    /// built somewhere else after it, so the run says nothing about it.
    public static let newerBuildTolerance: TimeInterval = 5 * 60

    /// - Parameters:
    ///   - imageRevision: the revision label from image inspect, used when the container has none.
    ///   - imageCreated: the image's created time from image inspect, used when the container has
    ///     no created label.
    public static func verdict(
        run: PublishRun?,
        container: PortainerContainer?,
        imageRevision: String? = nil,
        imageCreated: Date? = nil
    ) -> DeployVerdict {
        guard let run, let container else { return .unknown }
        let deployed = usableRevision(container.labels[revisionLabel]) ?? usableRevision(imageRevision)
        let created = container.labels[createdLabel].flatMap(CodeDate.parse) ?? imageCreated
        if let deployed {
            if revision(deployed, matches: run.headSHA) { return .current }
            if let created, created > run.completedAt.addingTimeInterval(newerBuildTolerance) { return .unknown }
            return .behind(builtAt: run.completedAt)
        }
        guard let created else { return .unknown }
        return created < run.completedAt.addingTimeInterval(-buildWindow) ? .behind(builtAt: run.completedAt) : .current
    }

    /// Two commit ids name the same commit when the shorter, at least 7 hex digits, starts the
    /// longer.
    public static func revision(_ lhs: String, matches rhs: String) -> Bool {
        guard let lhs = usableRevision(lhs), let rhs = usableRevision(rhs) else { return false }
        let length = min(lhs.count, rhs.count)
        return lhs.prefix(length) == rhs.prefix(length)
    }

    static func usableRevision(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              value.count >= 7, value.count <= 64, value.allSatisfy(\.isHexDigit) else { return nil }
        return value
    }
}

/// Finds the repositories the owner runs and works out each target's status.
enum DeployDiscovery {
    /// Workflow file name fragments, most likely to publish an image first.
    static let workflowKeywords = ["publish", "docker", "image", "release", "deploy", "build"]

    /// `owner/name` when `source` is a GitHub URL of a repository `login` owns, with the owner
    /// spelled as GitHub spells the login.
    static func repository(source: String, login: String) -> String? {
        guard let components = URLComponents(string: source.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host?.lowercased(), host == "github.com" || host == "www.github.com" else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0].caseInsensitiveCompare(login) == .orderedSame else { return nil }
        var name = parts[1]
        if name.lowercased().hasSuffix(".git") { name.removeLast(4) }
        let repository = "\(login)/\(name)"
        return (try? GitHubClient.repoPath(repository)) == nil ? nil : repository
    }

    static func ownedContainers(_ containers: [PortainerContainer], login: String) -> [String: [String]] {
        var byKey: [String: (repository: String, names: [String])] = [:]
        for container in containers where container.state == "running" {
            guard let source = container.labels[RevisionComparison.sourceLabel],
                  let repository = repository(source: source, login: login) else { continue }
            byKey[repository.lowercased(), default: (repository, [])].names.append(container.name)
        }
        return Dictionary(uniqueKeysWithValues: byKey.values.map { ($0.repository, $0.names.sorted()) })
    }

    static func guessWorkflow(_ workflows: [WorkflowFile]) -> String? {
        let names = workflows.filter(\.isActive).map(\.fileName).sorted()
        for keyword in workflowKeywords {
            if let match = names.first(where: { $0.lowercased().contains(keyword) }) { return match }
        }
        return nil
    }

    /// One target per owned repository with a guessable publish workflow, sorted by repository.
    /// `workflows` holds each repository's workflow files; one missing there gets no target.
    static func candidates(containers: [PortainerContainer], login: String, workflows: [String: [WorkflowFile]]) -> [DeployTarget] {
        ownedContainers(containers, login: login)
            .compactMap { repository, names -> DeployTarget? in
                guard let name = names.first, let files = workflows[repository], let workflow = guessWorkflow(files) else { return nil }
                return DeployTarget(repository: repository, workflow: workflow, containerName: name)
            }
            .sorted { $0.repository.lowercased() < $1.repository.lowercased() }
    }

    /// The running container a target names, or when it is gone (recreated under another name),
    /// the first running container built from the same repository.
    static func container(for target: DeployTarget, in containers: [PortainerContainer]) -> PortainerContainer? {
        let running = containers.filter { $0.state == "running" }
        if let named = running.first(where: { $0.name == target.containerName }) { return named }
        let owner = String(target.repository.split(separator: "/").first ?? "")
        return running
            .filter { container in
                container.labels[RevisionComparison.sourceLabel]
                    .flatMap { repository(source: $0, login: owner) }?
                    .caseInsensitiveCompare(target.repository) == .orderedSame
            }
            .min { $0.name < $1.name }
    }

    /// Whether the container needs image inspect: it has no usable revision label.
    static func needsImage(_ container: PortainerContainer) -> Bool {
        RevisionComparison.usableRevision(container.labels[RevisionComparison.revisionLabel]) == nil
    }

    static func statuses(
        targets: [DeployTarget],
        containers: [PortainerContainer],
        runs: [RunKey: PublishRun],
        images: [String: PortainerImage]
    ) -> [DeployStatus] {
        targets.map { target in
            let run = runs[RunKey(target)]
            let container = container(for: target, in: containers)
            let image = container.flatMap { images[$0.imageID] }
            let verdict = RevisionComparison.verdict(
                run: run,
                container: container,
                imageRevision: image?.labels[RevisionComparison.revisionLabel],
                imageCreated: image?.labels[RevisionComparison.createdLabel].flatMap(CodeDate.parse) ?? image?.created
            )
            return DeployStatus(target: target, run: run, container: container, verdict: verdict)
        }
    }

    /// Behind statuses, newest build first. `debugNudge` true raises one on the first status, using
    /// its run's time or `fallbackBuiltAt`; false hides them all.
    static func nudges(statuses: [DeployStatus], enabled: Bool, debugNudge: Bool?, fallbackBuiltAt: Date) -> [DeployStatus] {
        guard enabled, debugNudge != false else { return [] }
        var statuses = statuses
        if debugNudge == true, let first = statuses.first, !first.verdict.isBehind {
            statuses[0] = DeployStatus(
                target: first.target,
                run: first.run,
                container: first.container,
                verdict: .behind(builtAt: first.run?.completedAt ?? fallbackBuiltAt)
            )
        }
        return statuses
            .filter(\.verdict.isBehind)
            .sorted { lhs, rhs in
                builtAt(lhs) != builtAt(rhs) ? builtAt(lhs) > builtAt(rhs) : lhs.target.repository < rhs.target.repository
            }
    }

    private static func builtAt(_ status: DeployStatus) -> Date {
        if case .behind(let date) = status.verdict { return date }
        return .distantPast
    }
}

/// A repository's workflow, the key for its latest successful run.
struct RunKey: Hashable, Sendable {
    let repository: String
    let workflow: String

    init(repository: String, workflow: String) {
        self.repository = repository.lowercased()
        self.workflow = workflow
    }

    init(_ target: DeployTarget) {
        self.init(repository: target.repository, workflow: target.workflow)
    }
}
