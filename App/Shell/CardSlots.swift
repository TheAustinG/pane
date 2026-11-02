import PaneCore
import SwiftUI

/// The dashboard's fixed card positions from the approved mockup.
enum CardSlot: String, CaseIterable, Sendable {
    case current
    case forecast
    case home
    case code

    var size: CGSize {
        switch self {
        case .current: CGSize(width: Theme.Layout.weatherWidth, height: Theme.Layout.topRowHeight)
        case .forecast: CGSize(width: Theme.Layout.forecastWidth, height: Theme.Layout.bottomRowHeight)
        case .home, .code: CGSize(width: Theme.Layout.sideCardWidth, height: Theme.Layout.bottomRowHeight)
        }
    }
}

struct CardContext {
    let model: AppModel
    let date: Date
    let palette: ScenePalette
}

/// A card's content. The dashboard draws the glass pane, padding and focus around it; the card
/// fills `CardSlot.size` minus `Theme.Layout.paneInset`.
@MainActor
protocol DashboardCard: View {
    init(context: CardContext)
    /// What clicking the card does (radar for weather, scene buttons for Home). Default: nothing.
    static func activate(model: AppModel)
}

extension DashboardCard {
    static func activate(model: AppModel) {}
}

/// Each slot's card type lives in its feature's folder, so a later phase replaces its card
/// without editing the dashboard or this file.
enum CardSlots {
    @MainActor @ViewBuilder
    static func content(for slot: CardSlot, context: CardContext) -> some View {
        switch slot {
        case .current: CurrentWeatherCard(context: context)
        case .forecast: ForecastCard(context: context)
        case .home: HomeCard(context: context)
        case .code: CodeCard(context: context)
        }
    }

    @MainActor
    static func activate(_ slot: CardSlot, model: AppModel) {
        switch slot {
        case .current: CurrentWeatherCard.activate(model: model)
        case .forecast: ForecastCard.activate(model: model)
        case .home: HomeCard.activate(model: model)
        case .code: CodeCard.activate(model: model)
        }
    }
}
