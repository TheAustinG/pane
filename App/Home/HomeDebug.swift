#if DEBUG
import PaneCore
import SwiftUI

/// Debug menu row: raise each nudge, clear overrides, drop the socket.
struct HomeDebugRow: View {
    let model: AppModel

    private static let kinds: [(kind: HomeNudgeKind, title: String)] = [
        (.dryAir, "Dry"),
        (.humidAir, "Humid"),
        (.doorUnlockedLate, "Door"),
        (.lightsOnAway, "Lights"),
        (.bedroomTVLate, "TV"),
    ]

    var body: some View {
        let home = model.home
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                ForEach(Self.kinds, id: \.kind) { entry in
                    let active = home.nudges.contains { $0.kind == entry.kind }
                    Button {
                        home.debugOverrides = HomeFixtures.overrides(raising: entry.kind, selection: home.selection, base: home.entities)
                    } label: {
                        Label(entry.title, systemImage: active ? "checkmark.circle.fill" : "circle")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .accessibilityValue(active ? "active" : "")
                    .accessibilityIdentifier("debug.home.nudge.\(entry.kind.rawValue)")
                }
            }
            HStack(spacing: Theme.Space.m) {
                Button {
                    home.debugOverrides = [:]
                } label: {
                    Text("Clear").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("debug.home.clear")
                Button {
                    home.forceDisconnect()
                } label: {
                    Label("Drop connection", systemImage: "wifi.slash").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("debug.home.drop")
                Text(status)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Ink.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("debug.home.state")
            }
        }
    }

    private var status: String {
        let home = model.home
        let active = home.nudges.map(\.kind.rawValue).sorted().joined(separator: ", ")
        return "\(home.connection.stateName), \(home.reconnectCount) reconnects, nudges: \(active.isEmpty ? "none" : active)"
    }
}
#endif
