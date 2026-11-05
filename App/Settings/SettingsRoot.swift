import PaneCore
import SwiftUI

/// Settings: the registry's sections as a native list, with a help pane for the focused row.
struct SettingsRoot: View {
    let model: AppModel
    @State private var help = SettingsHelpState()
    @State private var preview = BackgroundPreview()

    private static let placeholder = "Choose a row to see what it does."

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            content(date: model.now(timeline.date))
        }
    }

    private func content(date: Date) -> some View {
        let palette = model.palette(at: date)
        return NavigationStack {
            HStack(alignment: .top, spacing: 80) {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("Settings")
                        .font(Theme.Typeface.screenTitle)
                        .accessibilityAddTraits(.isHeader)
                    SettingsHelpPane(text: help.text ?? Self.placeholder, qrURL: help.qrURL)
                }
                .frame(width: 620, alignment: .leading)
                List {
                    ForEach(Array(SettingsRegistry.availableSections().enumerated()), id: \.offset) { _, section in
                        Section(section.title) {
                            SettingsRegistry.rows(for: section, model: model)
                        }
                    }
                }
                .frame(width: 1000)
            }
            .padding(.vertical, Theme.Layout.marginVertical)
            .padding(.horizontal, Theme.Layout.marginHorizontal)
        }
        .background {
            ZStack {
                BackgroundView(
                    kind: preview.kind(in: model, at: date),
                    photo: model.photoKey(at: date),
                    palette: palette,
                    quality: model.quality,
                    particlesEnabled: false
                )
                Color.black.opacity(0.35).ignoresSafeArea()
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("Background preview")
                    .accessibilityValue((preview.mode ?? model.settings.backgroundMode).rawValue)
                    .accessibilityIdentifier("settings.background.preview")
            }
        }
        .environment(\.glassShade, palette.glassShade)
        .environment(\.settingsHelp, help)
        .environment(\.backgroundPreview, preview)
    }
}
