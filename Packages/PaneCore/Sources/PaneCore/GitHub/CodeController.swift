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

    /// The owner's chosen targets; nil watches every candidate.
    public var targets: [DeployTarget]? = nil
    /// Off hides the deploy nudge without stopping the checks.
    public var nudgeEnabled = true
    /// Debug: true raises a nudge on the first target, false hides every nudge, nil shows live state.
    public var debugNudge: Bool?
    /// App time for "today" and nudge ages; the app points it at its debug clock.
    @ObservationIgnored public var now: @MainActor () -> Date = { .now }
    /// Contribution days are counted in this calendar's time zone.
    @ObservationIgnored public var calendar: Calendar = .current

    public init(
        store: any KeyValueStore = UserDefaultsKeyValueStore(),
        secrets: any SecretStore,
        http: any HTTPClient,
        portainerHTTP: @escaping @Sendable (PortainerServer) -> any HTTPClient,
        clock: any WeatherClock = SystemWeatherClock()
    ) {}

    public var hasGitHubToken: Bool { false }
    public var hasPortainerToken: Bool { false }

    public var activeTargets: [DeployTarget] { targets ?? candidates }

    /// Targets that are behind, after `nudgeEnabled` and `debugNudge`, newest build first.
    public var nudges: [DeployStatus] { [] }

    /// Streak, today's count and grid levels for `weeks` columns ending at today's week.
    public func contributionSummary(weeks: Int = 26) -> ContributionSummary? { nil }

    /// Saves the token and refreshes with it.
    public func configureGitHub(token: String) throws {}

    /// Saves the server (with its pin) and token and refreshes with them.
    public func configurePortainer(server: PortainerServer, token: String) throws {}

    public func forgetGitHub() throws {}
    public func forgetPortainer() throws {}

    /// Clears everything `CodeController` saves, for the app's `-resetSettings`.
    public static func reset(store: any KeyValueStore = UserDefaultsKeyValueStore(), secrets: any SecretStore) {}

    /// Refreshes GitHub and the deploy targets on a timer, backing off after failures. Runs until
    /// the calling task is cancelled.
    public func run() async {}

    /// Starts the next refresh now instead of at its scheduled time.
    public func refreshNow() {}

    /// The GitHub setup screen's test: returns the token's login.
    public static func testGitHub(token: String, http: any HTTPClient) async -> Result<String, CodeSetupError> {
        .failure(.unreachable)
    }

    /// The Portainer setup screen's test: reads the version and container list, and reports the
    /// certificate's SHA-256 when the system does not trust it.
    public static func testPortainer(server: PortainerServer, token: String) async -> Result<PortainerServerInfo, CodeSetupError> {
        .failure(.unreachable)
    }

    /// A controller on the real code path against recorded-style responses built from these
    /// values. The caller still runs it.
    public static func preview(
        github: GitHubSnapshot,
        containers: [PortainerContainer],
        runs: [PublishRun],
        targets: [DeployTarget]? = nil
    ) -> CodeController {
        CodeController(
            store: InMemoryKeyValueStore(),
            secrets: InMemorySecretStore(),
            http: UnavailableHTTPClient(),
            portainerHTTP: { _ in UnavailableHTTPClient() }
        )
    }
}

struct UnavailableHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}
