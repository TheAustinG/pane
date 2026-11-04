import SwiftUI

enum DashboardFocus: Hashable {
    case settings
    case card(CardSlot)
    /// An invisible target that holds focus after a quiet spell, so no pane stays lit.
    case rest
}

struct DashboardView: View {
    @Bindable var model: AppModel
    var initialFocus: DashboardFocus?
    /// The design preview turns this off so its own Play/Pause steps through pages.
    var handlesDebugMenu = true
    /// The design preview keeps its chosen focus for screenshots.
    var releasesIdleFocus = true
    @FocusState private var focus: DashboardFocus?
    @State private var lastFocus: DashboardFocus = .card(.current)
    @State private var isResting = false
    /// Bumped by a card press, which does not always move focus.
    @State private var interactions = 0

    static let idleFocusDelay: Duration = .seconds(10)

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            screen(at: model.now(timeline.date))
        }
        .defaultFocus($focus, initialFocus ?? .card(.current))
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            if focus == nil, !model.isSettingsPresented, !model.isStormTakeoverShown { focus = initialFocus ?? .card(.current) }
        }
        .fullScreenCover(isPresented: $model.isSettingsPresented) {
            SettingsRoot(model: model)
        }
        .task(id: IdleKey(focus: focus, interactions: interactions)) {
            await releaseFocusWhenIdle()
        }
        .onChange(of: focus) { _, new in
            if let new, new != .rest {
                lastFocus = new
                isResting = false
            }
        }
        .onChange(of: model.isStormTakeoverShown) { _, shown in
            if shown { model.isHomeScenesPresented = false } else { focus = .card(.current) }
        }
        .onChange(of: model.isHomeScenesPresented) { _, presented in
            if !presented, !model.isStormTakeoverShown { focus = .card(.home) }
        }
        #if DEBUG
        .onPlayPauseCommand(perform: handlesDebugMenu ? { model.isDebugMenuPresented.toggle() } : nil)
        .onChange(of: model.isDebugMenuPresented) { _, presented in
            if !presented, !model.isStormTakeoverShown, !model.isHomeScenesPresented { focus = .card(.current) }
        }
        #endif
    }

    private struct IdleKey: Equatable {
        let focus: DashboardFocus?
        let interactions: Int
    }

    private func releaseFocusWhenIdle() async {
        guard releasesIdleFocus, let current = focus, current != .rest else { return }
        try? await Task.sleep(for: Self.idleFocusDelay)
        guard !Task.isCancelled, focus == current, !model.isHomeScenesPresented, !model.isSettingsPresented else { return }
        #if DEBUG
        guard !model.isDebugMenuPresented else { return }
        #endif
        isResting = true
        try? await Task.sleep(for: .milliseconds(50))
        if isResting, focus == current { focus = .rest }
    }

    private func wake() {
        isResting = false
        focus = lastFocus
    }

    /// Enabled only while resting, so ordinary navigation never lands on it.
    private var restTarget: some View {
        Button(action: wake) {
            Color.clear.frame(width: 160, height: 80)
        }
        .buttonStyle(RestButtonStyle())
        .disabled(!isResting)
        .focused($focus, equals: .rest)
        .onMoveCommand { _ in wake() }
        .accessibilityIdentifier("dashboard.rest")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, Theme.Layout.marginVertical)
    }

    private var isInteractive: Bool {
        #if DEBUG
        !model.isDebugMenuPresented
        #else
        true
        #endif
    }

    private func screen(at date: Date) -> some View {
        let palette = model.palette(at: date)
        let dimmed = model.isNightDimmed(at: date)
        let takeover = model.isStormTakeoverShown
        let context = CardContext(model: model, date: date, palette: palette)
        return ZStack {
            SkyView(target: palette, quality: model.quality, particlesEnabled: !dimmed && !takeover, animates: !model.isSettingsPresented && !takeover)
            if takeover {
                StormTakeover(model: model, date: date)
                    .disabled(!isInteractive)
                    .transition(.opacity)
            } else {
                Group {
                    layout(date: date, context: context)
                    settingsEntry
                    restTarget
                }
                .disabled(!isInteractive || model.isHomeScenesPresented)
                .transition(.opacity)
                if model.isHomeScenesPresented {
                    HomeScenesOverlay(model: model)
                        .disabled(!isInteractive)
                        .transition(.opacity)
                }
            }
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Storm takeover")
                .accessibilityValue(takeover ? "on" : "off")
                .accessibilityIdentifier("dashboard.stormTakeover")
            Color.black
                .opacity(dimmed ? 1 - Theme.Dim.night : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(Theme.Motion.nightDim, value: dimmed)
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Night dim")
                .accessibilityValue(dimmed ? "on" : "off")
                .accessibilityIdentifier("dashboard.nightDim")
            #if DEBUG
            DebugOverlay(model: model)
            #endif
        }
        .environment(\.marqueePaused, dimmed || takeover || model.isSettingsPresented)
        .animation(Theme.Motion.takeover, value: takeover)
        .animation(Theme.Motion.state, value: model.isHomeScenesPresented)
        .environment(\.glassShade, palette.glassShade)
    }

    private func layout(date: Date, context: CardContext) -> some View {
        let clock = ClockStrings(date: date, calendar: model.calendar)
        return VStack(spacing: Theme.Layout.gutter) {
            HStack(alignment: .top, spacing: Theme.Layout.gutter) {
                DashboardClock(time: clock.time, meridiem: clock.meridiem, date: clock.date)
                Spacer(minLength: 0)
                card(.current, context: context)
            }
            HStack(spacing: Theme.Layout.gutter) {
                card(.forecast, context: context)
                card(.home, context: context)
                card(.code, context: context)
            }
        }
        .padding(.vertical, Theme.Layout.marginVertical)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
    }

    private func card(_ slot: CardSlot, context: CardContext) -> some View {
        Button {
            interactions += 1
            CardSlots.activate(slot, model: model)
        } label: {
            CardSlots.content(for: slot, context: context)
                .padding(Theme.Layout.paneInset)
                .frame(width: slot.size.width, height: slot.size.height, alignment: .topLeading)
        }
        .buttonStyle(GlassPaneButtonStyle())
        .focused($focus, equals: .card(slot))
        .accessibilityIdentifier("dashboard.card.\(slot.rawValue)")
    }

    private var settingsEntry: some View {
        Button {
            model.isSettingsPresented = true
        } label: {
            Label("Settings", systemImage: "gearshape")
                .font(Theme.Typeface.body)
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, Theme.Space.s)
        }
        .buttonStyle(SettingsEntryStyle())
        .focused($focus, equals: .settings)
        .accessibilityIdentifier("dashboard.settings")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, Theme.Layout.marginHorizontal)
        .padding(.top, 4)
    }
}

/// Invisible until focused. The label is drawn clear rather than faded, because the focus engine
/// skips views at 0.01 opacity or below.
private struct SettingsEntryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusBody(configuration: configuration)
    }

    private struct FocusBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            if isFocused {
                configuration.label
                    .modifier(GlassPaneChrome(isFocused: true, isPressed: configuration.isPressed, cornerRadius: 40))
            } else {
                configuration.label.foregroundStyle(Color.clear)
            }
        }
    }
}

/// Draws nothing, focused or not. The content is clear rather than hidden, because the focus engine
/// skips views at 0.01 opacity or below.
private struct RestButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
