#if DEBUG
import PaneCore
import SwiftUI

/// Debug layer over the dashboard: the frame rate readout and, on Play/Pause, the debug panel.
struct DebugOverlay: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            if model.isDebugMenuPresented {
                Color.black.opacity(0.35).ignoresSafeArea()
                DebugMenu(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if model.showFPS {
                // Top center is the one strip no pane, clock or Settings button reaches.
                FrameHUD(quality: model.quality)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct DebugMenu: View {
    @Bindable var model: AppModel
    @FocusState private var focus: String?

    private static let steps: [(id: String, title: String, seconds: TimeInterval)] = [
        ("minus6h", "-6 h", -6 * 3600),
        ("minus1h", "-1 h", -3600),
        ("minus15m", "-15 m", -900),
        ("plus15m", "+15 m", 900),
        ("plus1h", "+1 h", 3600),
        ("plus6h", "+6 h", 6 * 3600),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("Debug")
                    .font(Theme.Typeface.headline)
                    .accessibilityIdentifier("debug.menu")
                Spacer(minLength: Theme.Space.l)
                appTime
            }
            section("Scene") { sceneGrid }
            section("Time") { timeRow }
            section("Display") {
                Toggle("FPS HUD", isOn: $model.showFPS)
                    .accessibilityIdentifier("debug.fps")
            }
            section("Quality") { qualityRow }
        }
        .padding(Theme.Layout.paneInset)
        .frame(width: 1240)
        .glassEffect(
            .regular.tint(Theme.Glass.shade.opacity(0.55)),
            in: RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius, style: .continuous)
        )
        .focusSection()
        .defaultFocus($focus, "scene.live")
        .onExitCommand { model.isDebugMenuPresented = false }
        .onAppear { focus = "scene.live" }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            PaneHeading(text: title)
            content()
        }
    }

    private var appTime: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let date = model.now(timeline.date)
            Text("App time \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute().second()))\(offsetText)")
                .font(Theme.Typeface.caption.monospacedDigit())
                .foregroundStyle(Theme.Ink.secondary)
                .accessibilityIdentifier("debug.time")
        }
    }

    private var offsetText: String {
        let minutes = Int((model.clock.offset / 60).rounded())
        guard minutes != 0 else { return "" }
        let sign = minutes < 0 ? "-" : "+"
        let magnitude = abs(minutes)
        let text = magnitude % 60 == 0 ? "\(magnitude / 60) h" : magnitude < 60 ? "\(magnitude) min" : "\(magnitude / 60) h \(magnitude % 60) min"
        return "  (\(sign)\(text))"
    }

    private var sceneGrid: some View {
        let names: [String?] = [nil] + WeatherScene.presetNames
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.m), count: 3), spacing: Theme.Space.m) {
            ForEach(names, id: \.self) { name in
                let selected = isSelected(name)
                Button {
                    model.sceneOverride = name.flatMap(WeatherScene.preset(named:))
                } label: {
                    Label((name ?? "Live").capitalized, systemImage: selected ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .focused($focus, equals: "scene.\(name ?? "live")")
                .accessibilityValue(selected ? "selected" : "")
                .accessibilityIdentifier("debug.scene.\(name ?? "live")")
            }
        }
    }

    private func isSelected(_ name: String?) -> Bool {
        guard let name else { return model.sceneOverride == nil }
        return model.sceneOverride != nil && model.sceneOverride == WeatherScene.preset(named: name)
    }

    private var timeRow: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach(Self.steps, id: \.id) { step in
                Button {
                    model.clock.offset += step.seconds
                } label: {
                    Text(step.title).lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("debug.time.\(step.id)")
            }
            Button {
                model.clock.offset = 0
            } label: {
                Text("Reset").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("debug.time.reset")
        }
    }

    private var qualityRow: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach(RenderQuality.all, id: \.name) { quality in
                let selected = model.quality == quality
                Button {
                    model.quality = quality
                } label: {
                    Label(quality.name.capitalized, systemImage: selected ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityValue(selected ? "selected" : "")
                .accessibilityIdentifier("debug.quality.\(quality.name)")
            }
        }
    }
}
#endif
