import SwiftUI

struct HomeCard: DashboardCard {
    let context: CardContext

    var body: some View {
        PaneHeading(text: "Home", symbol: "house")
    }
}
