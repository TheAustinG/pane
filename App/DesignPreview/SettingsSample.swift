#if DEBUG
import SwiftUI

/// Settings: native tvOS list rows on the right, and on the left a glass pane that explains
/// whichever row has focus.
struct SettingsSample: View {
    let scene: ScenePreset
    var focus: FocusState<String?>.Binding
    var scrollTarget: String?

    @State private var dimNow = false
    @State private var dryAir = true
    @State private var humidAir = true
    @State private var doorLate = true
    @State private var lightsAway = true
    @State private var bedroomTV = false

    private static let help: [String: String] = [
        "location": "Pane has no GPS. Search for your city once; it is stored as coordinates.",
        "background": "Gradient draws the sky live. Photo uses a blurred photo for the scene. Auto uses photos by day and the gradient at night and in storms.",
        "stormLayout": "Where the weather strip sits when radar takes over: a column at the side, or a strip along the bottom.",
        "nightSchedule": "The dashboard dims to about 30 percent overnight. Storm mode and nudges still brighten it.",
        "dimNow": "Dim the dashboard until the schedule next ends.",
        "homeAssistant": "Server address and access token for a non-admin Home Assistant user.",
        "github": "A fine-grained token with read-only Contents, Metadata and Actions.",
        "portainer": "Used for the redeploy nudge: compares the running container's revision with the latest build.",
        "dryAir": "Shows a nudge on the Home card when indoor humidity drops below 35 percent.",
        "attribution": "Weather data comes from Apple Weather. Scan for the data sources and legal notice.",
    ]

    var body: some View {
        ZStack {
            PreviewSky(scene: scene, particles: false)
            Color.black.opacity(0.35).ignoresSafeArea()
            HStack(alignment: .top, spacing: 80) {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("Settings").font(Theme.Typeface.screenTitle)
                    helpPane
                }
                .frame(width: 620, alignment: .leading)
                ScrollViewReader { proxy in
                List {
                    Section("Weather") {
                        valueRow("location", "Location", "Springfield")
                        valueRow("background", "Background", "Gradient")
                        valueRow("stormLayout", "Storm strip", "Side")
                    }
                    Section("Night") {
                        valueRow("nightSchedule", "Night dim", "11:00 PM to 6:30 AM")
                        toggleRow("dimNow", "Dim now", $dimNow)
                    }
                    Section("Services") {
                        valueRow("homeAssistant", "Home Assistant", "Connected")
                        valueRow("github", "GitHub", "Connected")
                        valueRow("portainer", "Portainer", "Not set up")
                    }
                    Section("Nudges") {
                        toggleRow("dryAir", "Dry air below 35%", $dryAir)
                        toggleRow("humidAir", "Humid air above 60%", $humidAir)
                        toggleRow("doorLate", "Door unlocked after 10 PM", $doorLate)
                        toggleRow("lightsAway", "Lights on with nobody home", $lightsAway)
                        toggleRow("bedroomTV", "Bedroom TV on after midnight", $bedroomTV)
                    }
                    Section("About") {
                        valueRow("attribution", "Weather data", "Apple Weather")
                    }
                }
                .onAppear {
                    if let scrollTarget { proxy.scrollTo(scrollTarget, anchor: .center) }
                }
                }
                .frame(width: 1000)
            }
            .padding(.vertical, Theme.Layout.marginVertical)
            .padding(.horizontal, Theme.Layout.marginHorizontal)
        }
        .environment(\.glassShade, scene.glassShade)
    }

    private var helpPane: some View {
        let key = focus.wrappedValue ?? "location"
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(Self.help[key] ?? "")
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if key == "attribution", let url = URL(string: "https://weatherkit.apple.com/legal-attribution.html") {
                QRCodeView(url: url, side: 220)
            }
            if key == "stormLayout" {
                HStack(spacing: Theme.Space.l) {
                    LayoutDiagram(side: true, selected: true)
                    LayoutDiagram(side: false, selected: false)
                }
            }
        }
        .padding(Theme.Layout.paneInset)
        .frame(width: 620, alignment: .leading)
        .glassPane()
        .animation(Theme.Motion.state, value: key)
    }

    private func valueRow(_ id: String, _ title: String, _ value: String) -> some View {
        Button {} label: {
            LabeledContent(title, value: value)
        }
        .focused(focus, equals: id)
        .id(id)
        .accessibilityIdentifier("preview.settings.\(id)")
    }

    private func toggleRow(_ id: String, _ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .focused(focus, equals: id)
            .id(id)
            .accessibilityIdentifier("preview.settings.\(id)")
    }
}

private struct LayoutDiagram: View {
    let side: Bool
    let selected: Bool

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            ZStack(alignment: side ? .trailing : .bottom) {
                RoundedRectangle(cornerRadius: 10).fill(Theme.Ink.faint)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.Ink.secondary)
                    .frame(width: side ? 46 : nil, height: side ? nil : 26)
                    .padding(8)
            }
            .frame(width: 200, height: 112)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Theme.Ink.primary : Theme.Ink.rule, lineWidth: selected ? 3 : 1)
            }
            Text(side ? "Side" : "Bottom")
                .font(Theme.Typeface.caption)
                .foregroundStyle(selected ? Theme.Ink.primary : Theme.Ink.secondary)
        }
    }
}
#endif
