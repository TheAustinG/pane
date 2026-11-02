import SwiftUI

/// The clock and date that sit directly on the sky, top left.
struct DashboardClock: View {
    let time: String
    let meridiem: String
    let date: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 20) {
            HStack(alignment: .firstTextBaseline, spacing: compact ? 10 : 18) {
                Text(time)
                    .font(compact ? .system(size: 112, weight: .thin) : Theme.Typeface.clock)
                    .tracking(compact ? -3 : -8)
                Text(meridiem)
                    .font(compact ? .system(size: 36, weight: .light) : Theme.Typeface.meridiem)
                    .opacity(0.9)
            }
            .padding(.top, compact ? 0 : -40)
            Text(date)
                .font(compact ? Theme.Typeface.callout : Theme.Typeface.date)
                .opacity(0.92)
        }
        .lineLimit(1)
        .shadow(color: Theme.Glass.textShadow, radius: 15, y: 2)
        .accessibilityElement(children: .combine)
    }
}

struct ClockStrings {
    let time: String
    let meridiem: String
    let date: String

    init(date: Date, calendar: Calendar) {
        func format(_ pattern: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = pattern
            return formatter.string(from: date)
        }
        time = format("h:mm")
        meridiem = format("a")
        self.date = format("EEEE, MMMM d")
    }
}
