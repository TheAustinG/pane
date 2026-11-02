import SwiftUI

enum DashboardFocus: Hashable {
    case settings
    case card(CardSlot)
}

struct DashboardView: View {
    @Bindable var model: AppModel
    var initialFocus: DashboardFocus?
    /// The design preview turns this off so its own Play/Pause steps through pages.
    var handlesDebugMenu = true
    @FocusState private var focus: DashboardFocus?

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            screen(at: model.now(timeline.date))
        }
        .defaultFocus($focus, initialFocus ?? .card(.current))
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            if focus == nil, !model.isSettingsPresented { focus = initialFocus ?? .card(.current) }
        }
        .fullScreenCover(isPresented: $model.isSettingsPresented) {
            SettingsRoot(model: model)
        }
        #if DEBUG
        .onPlayPauseCommand(perform: handlesDebugMenu ? { model.isDebugMenuPresented.toggle() } : nil)
        .onChange(of: model.isDebugMenuPresented) { _, presented in
            if !presented { focus = .card(.current) }
        }
        #endif
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
        let context = CardContext(model: model, date: date, palette: palette)
        return ZStack {
            SkyView(target: palette, quality: model.quality, particlesEnabled: !dimmed)
            layout(date: date, context: context)
                .disabled(!isInteractive)
            settingsEntry
                .disabled(!isInteractive)
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
