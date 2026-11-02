import SwiftUI

struct CodeCard: DashboardCard {
    let context: CardContext

    var body: some View {
        PaneHeading(text: "GitHub", symbol: "arrow.triangle.branch")
    }
}
