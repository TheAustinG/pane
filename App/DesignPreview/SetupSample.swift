#if DEBUG
import SwiftUI

enum SetupSampleState: String {
    case empty
    case testing
    case ok
    case error
}

/// A service setup screen. Fields and actions stack vertically because tvOS moves focus to the
/// geometrically nearest control, so a side-by-side row under a wide field sends Down to the
/// wrong button.
struct SetupSample: View {
    let scene: ScenePreset
    let state: SetupSampleState
    var focus: FocusState<String?>.Binding

    @State private var address = ""
    @State private var token = ""

    var body: some View {
        ZStack {
            PreviewSky(scene: scene, particles: false)
            Color.black.opacity(0.35).ignoresSafeArea()
            HStack(alignment: .top, spacing: 96) {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Image(systemName: "house")
                        .font(.system(size: 64, weight: .light))
                        .frame(width: 132, height: 132)
                        .glassPane()
                    Text("Connect Home Assistant").font(Theme.Typeface.screenTitle)
                    Text("Use a long-lived access token from a Home Assistant user without admin rights. Focus a field and accept the keyboard prompt on your iPhone to paste it.")
                        .font(Theme.Typeface.body)
                        .foregroundStyle(Theme.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 680, alignment: .leading)
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    TextField("Server address", text: $address, prompt: Text("http://homeassistant.local:8123"))
                        .focused(focus, equals: "address")
                        .accessibilityIdentifier("preview.setup.address")
                    SecureField("Access token", text: $token, prompt: Text("Long-lived access token"))
                        .focused(focus, equals: "token")
                        .accessibilityIdentifier("preview.setup.token")
                    status
                        .frame(minHeight: 72, alignment: .leading)
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        Button {} label: { Text("Test connection").frame(width: 400) }
                            .buttonStyle(.glass)
                            .focused(focus, equals: "test")
                        Button {} label: { Text("Save").frame(width: 400) }
                            .buttonStyle(.glass)
                            .disabled(state != .ok)
                            .focused(focus, equals: "save")
                        Button {} label: { Text("Not now").frame(width: 400) }
                            .buttonStyle(.glass)
                            .focused(focus, equals: "cancel")
                    }
                }
                .frame(width: 860, alignment: .leading)
            }
            .padding(.top, 140)
            .padding(.horizontal, Theme.Layout.marginHorizontal)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .environment(\.glassShade, scene.glassShade)
        .onAppear {
            if state != .empty {
                address = "http://homeassistant.local:8123"
                token = "sample-token-for-preview-only"
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch state {
        case .empty:
            Text("Both fields are needed before Pane can connect.")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
        case .testing:
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text("Testing connection").font(Theme.Typeface.body)
            }
        case .ok:
            StatusRow(symbol: "checkmark", title: "Connected", detail: "Home Assistant 2026.10, 152 entities")
        case .error:
            NudgeChip(
                text: "Could not reach the server. Check the address and that the Apple TV is on the same network.",
                symbol: "exclamationmark.triangle.fill",
                tone: .warning
            )
        }
    }
}
#endif
