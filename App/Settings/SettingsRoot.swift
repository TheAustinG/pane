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
        let background = model.background(at: date, mode: preview.mode)
        let palette = background.palette
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
                    kind: background.kind,
                    photo: background.photo,
                    palette: palette,
                    quality: model.quality,
                    particlesEnabled: false
                )
                Color.black.opacity(0.35).ignoresSafeArea()
                AccessibilityMarker(
                    label: "Background preview",
                    value: (preview.mode ?? model.settings.backgroundMode).rawValue,
                    id: "settings.background.preview"
                )
            }
        }
        .environment(\.glassShade, palette.glassShade)
        .environment(\.settingsHelp, help)
        .environment(\.backgroundPreview, preview)
    }
}
