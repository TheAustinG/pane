import PaneCore
import SwiftUI

struct CodeCard: DashboardCard {
    let context: CardContext

    var body: some View {
        let code = context.model.code
        let accent = context.palette.accent
        CodeContent(
            github: code.github,
            connection: code.githubConnection,
            portainerConnection: code.portainerConnection,
            summary: code.contributionSummary(),
            nudges: code.nudges,
            now: context.date,
            accent: Color(red: accent.red, green: accent.green, blue: accent.blue)
        )
    }
}

private struct CodeContent: View {
    let github: GitHubSnapshot?
    let connection: CodeConnection
    let portainerConnection: CodeConnection
    let summary: ContributionSummary?
    let nudges: [DeployStatus]
    let now: Date
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            header
            if let github {
                snapshot(github)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("GitHub connection")
                .accessibilityValue("github: \(connection.stateName), portainer: \(portainerConnection.stateName)")
                .accessibilityIdentifier("code.card")
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            PaneHeading(text: "GitHub", symbol: "arrow.triangle.branch")
            Spacer(minLength: 0)
            switch connection {
            case .authFailed:
                NudgeChip(text: "GitHub token rejected", symbol: "key.slash", tone: .warning)
                    .accessibilityIdentifier("code.warning")
            case .failed:
                NudgeChip(text: "GitHub unreachable", symbol: "wifi.exclamationmark", tone: .warning)
                    .accessibilityIdentifier("code.warning")
            default:
                EmptyView()
            }
        }
        .frame(height: 30)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch connection {
        case .notConfigured:
            line("Set up in Settings")
        case .loading, .ready:
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text("Loading").font(Theme.Typeface.body).foregroundStyle(Theme.Ink.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("code.state")
        case .authFailed:
            line("Update the token in Settings")
        case .failed:
            line("Cannot reach GitHub")
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.Ink.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("code.state")
    }

    private func snapshot(_ github: GitHubSnapshot) -> some View {
        let nudgeText = CodeText.nudgeText(nudges, now: now)
        return VStack(alignment: .leading, spacing: 0) {
            if let summary {
                streakRow(summary)
                Spacer(minLength: Theme.Space.s)
                ContributionGrid(levels: summary.levels, accent: accent)
                    .accessibilityIdentifier("code.grid")
            }
            if let commit = github.latestCommit {
                Spacer(minLength: Theme.Space.s)
                commitRow(commit)
            }
            if let nudgeText {
                Spacer(minLength: Theme.Space.s)
                NudgeChip(text: nudgeText, symbol: "shippingbox")
                    .accessibilityIdentifier("code.nudge")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(connection == .ready || connection == .loading ? 1 : 0.62)
    }

    private func streakRow(_ summary: ContributionSummary) -> some View {
        HStack {
            Label {
                Text(summary.streak > 0 ? "\(summary.streak)-day streak" : "No streak")
            } icon: {
                Image(systemName: "flame").foregroundStyle(Theme.Signal.nudge)
            }
            .font(Theme.Typeface.headline)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("code.streak")
            Spacer(minLength: Theme.Space.s)
            Text("\(summary.todayCount) today")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
                .accessibilityIdentifier("code.today")
        }
        .lineLimit(1)
    }

    private func commitRow(_ commit: LatestCommit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Space.xs) {
                Text(commit.repositoryName).font(Theme.Typeface.subheadStrong)
                Text(CodeText.age(from: commit.date, now: now))
                    .font(Theme.Typeface.subhead)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
            Text(commit.headline)
                .font(Theme.Typeface.subhead)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("code.commit")
    }
}
