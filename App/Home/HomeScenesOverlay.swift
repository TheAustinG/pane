import PaneCore
import SwiftUI

/// The scene buttons, opened by clicking the Home card.
struct HomeScenesOverlay: View {
    @Bindable var model: AppModel
    @State private var result: SceneResult?
    @State private var running: String?
    @FocusState private var focus: String?

    private enum SceneResult: Equatable {
        case ran(String)
        case failed(String)
    }

    private static let closeID = "close"
    private static let columns = 4

    private var home: HomeController { model.home }
    private var scenes: [HAEntity] {
        home.selection.scenes.map { home.entities[$0] ?? HAEntity(entityID: $0, state: "unavailable") }
    }

    private var canRun: Bool { home.connection.isConnected && !scenes.isEmpty }

    /// Back needs something focusable to hear it, so a panel with every button disabled gets a Close
    /// button.
    private var firstFocusID: String { canRun ? scenes[0].entityID : Self.closeID }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45).ignoresSafeArea()
            panel
                .offset(x: Theme.Layout.marginHorizontal + Theme.Layout.forecastWidth + Theme.Layout.gutter
                    + Theme.Layout.sideCardWidth / 2 - Theme.Layout.canvas.width / 2)
                .padding(.bottom, Theme.Layout.marginVertical + Theme.Layout.bottomRowHeight + Theme.Layout.gutter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($focus, firstFocusID)
        .onExitCommand { model.isHomeScenesPresented = false }
        .task {
            // The focus engine can ignore `defaultFocus` while the dashboard it replaces still holds focus.
            try? await Task.sleep(for: .milliseconds(600))
            if focus == nil { focus = firstFocusID }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.scenes")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            PaneHeading(text: "Scenes", symbol: "sparkles")
            if scenes.isEmpty {
                note("Choose scene buttons in Settings, under Home.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(Array(stride(from: 0, to: scenes.count, by: Self.columns)), id: \.self) { start in
                        HStack(spacing: Theme.Space.m) {
                            ForEach(scenes[start..<min(start + Self.columns, scenes.count)]) { scene in
                                sceneButton(scene)
                            }
                        }
                    }
                }
            }
            if let reason = disabledReason {
                note(reason)
            }
            resultLine
            if !canRun {
                Button { model.isHomeScenesPresented = false } label: { Text("Close").frame(width: 200) }
                    .buttonStyle(.glass)
                    .focused($focus, equals: Self.closeID)
                    .accessibilityIdentifier("home.scenes.close")
            }
        }
        .padding(Theme.Layout.paneInset)
        .background(
            Theme.Glass.shade.opacity(0.7),
            in: RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius, style: .continuous)
        )
        .glassPane()
    }

    private func sceneButton(_ scene: HAEntity) -> some View {
        Button {
            Task { await run(scene) }
        } label: {
            Label(scene.friendlyName, systemImage: Self.symbol(for: scene))
                .lineLimit(1)
        }
        .buttonStyle(.glass)
        .disabled(!canRun)
        .focused($focus, equals: scene.entityID)
        .accessibilityIdentifier("home.scene.\(scene.entityID)")
    }

    private var disabledReason: String? {
        switch home.connection {
        case .connected: nil
        case .notConfigured: "Home Assistant is not set up. Scenes are unavailable."
        case .connecting: "Connecting to Home Assistant. Scenes are unavailable until it connects."
        case .disconnected: "Home Assistant is unreachable. Scenes are unavailable until it reconnects."
        case .authFailed: "Home Assistant rejected the token. Update it in Settings."
        }
    }

    private var resultLine: some View {
        Group {
            switch result {
            case .ran(let name):
                Label("Ran \(name)", systemImage: "checkmark")
                    .foregroundStyle(Theme.Ink.secondary)
            case .failed(let message):
                NudgeChip(text: message, symbol: "exclamationmark.triangle.fill", tone: .warning)
            case nil:
                Text(running.map { "Running \(home.entities[$0]?.friendlyName ?? $0)" } ?? " ")
                    .foregroundStyle(Theme.Ink.secondary)
            }
        }
        .font(Theme.Typeface.caption)
        .frame(minHeight: 32, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.scenes.result")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 560, alignment: .leading)
            .accessibilityIdentifier("home.scenes.note")
    }

    private func run(_ scene: HAEntity) async {
        guard running == nil else { return }
        running = scene.entityID
        result = nil
        defer { running = nil }
        do {
            try await home.activateScene(scene.entityID)
            result = .ran(scene.friendlyName)
            if scene.entityID == home.selection.goodnightEntityID(in: home.entities) {
                model.startNightDim()
                model.isHomeScenesPresented = false
            }
        } catch {
            result = .failed("Could not run \(scene.friendlyName)")
        }
    }

    private static func symbol(for scene: HAEntity) -> String {
        let text = "\(scene.friendlyName) \(scene.entityID)".lowercased()
        let table: [(words: [String], symbol: String)] = [
            (["goodnight", "good night", "good_night", "bedtime", "sleep"], "moon.zzz"),
            (["movie", "film", "cinema", "theater", "theatre"], "film"),
            (["morning", "wake", "sunrise"], "sun.horizon"),
            (["away", "leaving", "leave"], "figure.walk"),
            (["dinner", "kitchen"], "fork.knife"),
            (["relax", "chill", "evening"], "sofa"),
            (["party"], "party.popper"),
        ]
        return table.first { entry in entry.words.contains { text.contains($0) } }?.symbol ?? "sparkles"
    }
}
