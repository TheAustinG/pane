import SwiftUI

/// The Setup layout: a 680 pt column with a glass icon, title and instructions beside an 860 pt
/// column of fields, a status line and stacked actions.
struct CodeSetupLayout<Fields: View>: View {
    let symbol: String
    let title: String
    let instructions: String
    var topPadding: CGFloat = 140
    @ViewBuilder let fields: Fields

    var body: some View {
        HStack(alignment: .top, spacing: 96) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Image(systemName: symbol)
                    .font(.system(size: 64, weight: .light))
                    .frame(width: 132, height: 132)
                    .glassPane()
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.Typeface.screenTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(instructions)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 680, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                fields
            }
            .frame(width: 860, alignment: .leading)
        }
        .padding(.top, topPadding)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
