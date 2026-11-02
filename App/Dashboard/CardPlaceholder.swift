import SwiftUI

/// What a card shows until its feature supplies data: the pane heading and one quiet line.
struct CardPlaceholder: View {
    let heading: String
    var symbol: String?
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            PaneHeading(text: heading, symbol: symbol)
            Text(line)
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
