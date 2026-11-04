#if DEBUG
import Foundation
import PaneCore

/// Sample GitHub and Portainer data for repeatable Code card states. Invented names only.
enum CodeFixtures {
    /// `behind` makes the sample container run an older revision than the latest publish run.
    @MainActor
    static func controller(behind: Bool) -> CodeController {
        CodeController.preview(
            github: GitHubSnapshot(login: "sample", calendar: ContributionCalendar(days: []), latestCommit: nil, fetchedAt: .now),
            containers: [],
            runs: []
        )
    }
}
#endif
