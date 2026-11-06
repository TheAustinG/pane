import PaneCore
import SwiftUI

/// Gradient, Photo or Auto, and where the photos came from.
enum BackgroundSettingsSection: SettingsSection {
    static let title = "Background"

    static func rows(model: AppModel) -> some View {
        BackgroundSettingsRows(model: model)
    }

    static let modeHelp = "A drifting gradient, a blurred photo of the sky, or whichever suits the time of day."
    static let creditsHelp = "The photographer and license for each background photo."
}

private struct BackgroundSettingsRows: View {
    let model: AppModel

    var body: some View {
        NavigationLink {
            BackgroundChoiceScreen(model: model)
        } label: {
            LabeledContent("Background", value: model.settings.backgroundMode.label)
        }
        .settingsHelp(BackgroundSettingsSection.modeHelp)
        .accessibilityIdentifier("settings.background.mode")

        NavigationLink {
            PhotoCreditsScreen()
        } label: {
            LabeledContent("Photo credits", value: PhotoCreditsScreen.summary)
        }
        .settingsHelp(BackgroundSettingsSection.creditsHelp)
        .accessibilityIdentifier("settings.background.credits")
    }
}
