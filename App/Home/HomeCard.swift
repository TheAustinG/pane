import SwiftUI

struct HomeCard: DashboardCard {
    let context: CardContext

    static func activate(model: AppModel) {
        model.isHomeScenesPresented = true
    }

    var body: some View {
        #if DEBUG
        if context.model.usesSampleFixtures {
            HomeContent()
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        CardPlaceholder(heading: "Home", symbol: "house", line: "Not connected yet")
    }
}

#if DEBUG
private struct HomeContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            PaneHeading(text: "Home", symbol: "house")
            VStack(alignment: .leading, spacing: 0) {
                StatusRow(symbol: "thermometer.medium", title: "70° inside", detail: "Heating to 69°")
                Spacer(minLength: 0)
                StatusRow(symbol: "humidity", title: "31% humidity", detail: "Bedroom 33%") {
                    NudgeChip(text: "Dry air")
                }
                Spacer(minLength: 0)
                StatusRow(symbol: "lock", title: "Front door locked", detail: "Since 3:58 PM")
                Spacer(minLength: 0)
                StatusRow(symbol: "lightbulb", title: "3 lights on", detail: "Kitchen, Living Room, Hall")
                Spacer(minLength: 0)
                StatusRow(symbol: "person.2", title: "Everyone's home") {
                    HStack(spacing: -10) {
                        Avatar(text: "A", fill: 0.28)
                        Avatar(text: "+1", fill: 0.2)
                    }
                }
            }
        }
    }
}

private struct Avatar: View {
    let text: String
    let fill: Double

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 40, height: 40)
            .background(.white.opacity(fill), in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2) }
    }
}
#endif
