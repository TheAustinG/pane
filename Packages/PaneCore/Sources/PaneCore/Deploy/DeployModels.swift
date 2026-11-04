import Foundation

/// Where Portainer lives and which environment holds the containers. The address is typed on the
/// setup screen, so a bare `host:port` is accepted and means https.
public struct PortainerServer: Hashable, Sendable, Codable {
    public let baseURL: URL
    public let environmentID: Int
    /// SHA-256 of the leaf certificate, lowercase hex, pinned at setup (trust on first use). Nil for
    /// plain http or a certificate the system already trusts.
    public var pinnedCertificateSHA256: String?

    public init?(address: String, environmentID: Int, pinnedCertificateSHA256: String? = nil) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, environmentID > 0 else { return nil }
        let text = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty else { return nil }
        parts.scheme = scheme
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { return nil }
        baseURL = url
        self.environmentID = environmentID
        self.pinnedCertificateSHA256 = pinnedCertificateSHA256
    }

    public var address: String { baseURL.absoluteString }
}

/// What a successful Portainer connection test found.
public struct PortainerServerInfo: Hashable, Sendable {
    public let version: String
    public let containerCount: Int
    /// The leaf certificate's SHA-256 when the system does not trust it; the setup screen shows it
    /// and saving pins it.
    public let certificateSHA256: String?

    public init(version: String, containerCount: Int, certificateSHA256: String?) {
        self.version = version
        self.containerCount = containerCount
        self.certificateSHA256 = certificateSHA256
    }
}

/// A running container as Portainer's Docker proxy lists it.
public struct PortainerContainer: Hashable, Sendable, Codable {
    public let id: String
    /// Without Docker's leading slash.
    public let name: String
    public let image: String
    public let imageID: String
    public let state: String
    public let created: Date
    public let labels: [String: String]

    public init(id: String, name: String, image: String, imageID: String, state: String, created: Date, labels: [String: String]) {
        self.id = id
        self.name = name
        self.image = image
        self.imageID = imageID
        self.state = state
        self.created = created
        self.labels = labels
    }
}

/// The newest successful run of a repository's publish workflow.
public struct PublishRun: Hashable, Sendable, Codable {
    public let repository: String
    /// Workflow file name, such as `publish.yml`.
    public let workflow: String
    public let headSHA: String
    /// When the run finished, which is when the image was pushed.
    public let completedAt: Date

    public init(repository: String, workflow: String, headSHA: String, completedAt: Date) {
        self.repository = repository
        self.workflow = workflow
        self.headSHA = headSHA
        self.completedAt = completedAt
    }
}

/// A repository whose image the owner runs, and the container that runs it.
public struct DeployTarget: Hashable, Sendable, Codable, Identifiable {
    /// `owner/name`.
    public let repository: String
    /// Workflow file name, such as `publish.yml`.
    public var workflow: String
    public var containerName: String

    public init(repository: String, workflow: String, containerName: String) {
        self.repository = repository
        self.workflow = workflow
        self.containerName = containerName
    }

    public var id: String { repository }

    public var repositoryName: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}

public enum DeployVerdict: Hashable, Sendable {
    /// The container runs the latest published revision.
    case current
    /// A newer image was published at `builtAt` and the container still runs an older one.
    case behind(builtAt: Date)
    /// Not enough to compare: no successful run, no container, or neither a revision label nor an
    /// image time.
    case unknown

    public var isBehind: Bool {
        if case .behind = self { return true }
        return false
    }
}

/// One target's latest comparison.
public struct DeployStatus: Hashable, Sendable {
    public let target: DeployTarget
    public let run: PublishRun?
    public let container: PortainerContainer?
    public let verdict: DeployVerdict

    public init(target: DeployTarget, run: PublishRun?, container: PortainerContainer?, verdict: DeployVerdict) {
        self.target = target
        self.run = run
        self.container = container
        self.verdict = verdict
    }
}
