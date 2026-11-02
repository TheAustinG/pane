import SwiftUI

struct CodeCard: DashboardCard {
    let context: CardContext

    var body: some View {
        #if DEBUG
        if context.model.usesSampleFixtures {
            let accent = context.palette.accent
            CodeContent(accent: Color(red: accent.red, green: accent.green, blue: accent.blue))
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        CardPlaceholder(heading: "GitHub", symbol: "arrow.triangle.branch", line: "Not connected yet")
    }
}

#if DEBUG
private struct CodeContent: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeading(text: "GitHub", symbol: "arrow.triangle.branch")
            Spacer(minLength: Theme.Space.s)
            HStack {
                Label {
                    Text("12-day streak")
                } icon: {
                    Image(systemName: "flame").foregroundStyle(Theme.Signal.nudge)
                }
                .font(Theme.Typeface.headline)
                Spacer(minLength: Theme.Space.s)
                Text("4 today")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            ContributionGrid(levels: ScenePreset.contributionLevels, accent: accent)
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xs) {
                    Text("pane").font(Theme.Typeface.subheadStrong)
                    Text("2h ago")
                        .font(Theme.Typeface.subhead)
                        .foregroundStyle(Theme.Ink.tertiary)
                }
                Text("Tune glass pane focus lift")
                    .font(Theme.Typeface.subhead)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            NudgeChip(text: "pane image built 3h ago, not redeployed", symbol: "shippingbox")
        }
    }
}
#endif
