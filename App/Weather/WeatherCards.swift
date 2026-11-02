import SwiftUI

struct CurrentWeatherCard: DashboardCard {
    let context: CardContext

    var body: some View {
        PaneHeading(text: "Weather")
    }
}

struct ForecastCard: DashboardCard {
    let context: CardContext

    var body: some View {
        PaneHeading(text: "Forecast")
    }
}
