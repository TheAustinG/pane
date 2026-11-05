#if DEBUG
import Foundation
import PaneCore

/// Sample GitHub and Portainer data for repeatable Code card states. Invented names only.
enum CodeFixtures {
    private static let lantern = DeployTarget(repository: "sample/lantern", workflow: "publish.yml", containerName: "lantern")
    private static let paneSample = DeployTarget(repository: "sample/pane-sample", workflow: "release.yml", containerName: "pane-sample")

    /// `behind` makes the sample containers run an older revision than the latest publish runs.
    /// Times are relative to `now`, which is the real clock unless the caller passes its frozen one.
    @MainActor
    static func controller(behind: Bool, now: Date = .now) -> CodeController {
        let targets = [lantern, paneSample]
        let hours: [TimeInterval] = [3, 6]
        var containers: [PortainerContainer] = []
        var runs: [PublishRun] = []
        for (index, target) in targets.enumerated() {
            let published = sha(index * 2 + 1)
            let running = behind ? sha(index * 2 + 2) : published
            containers.append(PortainerContainer(
                id: "c0ffee\(index)",
                name: target.containerName,
                image: "ghcr.io/\(target.repository):latest",
                imageID: "sha256:\(sha(index + 7))",
                state: "running",
                created: now.addingTimeInterval(-5 * 86_400),
                labels: [
                    RevisionComparison.revisionLabel: running,
                    RevisionComparison.sourceLabel: "https://github.com/\(target.repository)",
                ]
            ))
            runs.append(PublishRun(
                repository: target.repository,
                workflow: target.workflow,
                headSHA: published,
                completedAt: now.addingTimeInterval(-hours[index] * 3600)
            ))
        }
        let snapshot = GitHubSnapshot(
            login: "sample",
            calendar: calendar(around: now),
            latestCommit: LatestCommit(
                repository: "sample/lantern",
                branch: "main",
                sha: sha(9),
                headline: "Tune glass pane focus lift",
                date: now.addingTimeInterval(-2 * 3600)
            ),
            fetchedAt: now
        )
        return CodeController.preview(github: snapshot, containers: containers, runs: runs, targets: [lantern])
    }

    /// A deterministic calendar from 400 days before `date` through 30 days after.
    static func calendar(around date: Date) -> ContributionCalendar {
        let calendar = Calendar.current
        var days: [ContributionDay] = []
        for offset in -400...30 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            let ordinal = calendar.ordinality(of: .day, in: .era, for: day) ?? 0
            let count = contributions(onDay: ordinal)
            days.append(ContributionDay(day: CalendarDay(date: day, calendar: calendar), count: count, level: level(for: count)))
        }
        return ContributionCalendar(days: days)
    }

    private static func contributions(onDay ordinal: Int) -> Int {
        let mix = (ordinal * 37 + (ordinal / 7) * 11) % 13
        if ordinal % 11 == 0 || mix < 2 { return 0 }
        return mix - 1
    }

    private static func level(for count: Int) -> Int {
        switch count {
        case 0: 0
        case 1...2: 1
        case 3...5: 2
        case 6...8: 3
        default: 4
        }
    }

    private static func sha(_ seed: Int) -> String {
        let unit = String(format: "%08lx", 0x1a2b_3c4d &* (seed + 1) & 0xffff_ffff)
        return String(repeating: unit, count: 5)
    }
}
#endif
