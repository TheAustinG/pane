import Observation
import PaneCore
import SwiftUI

/// The mode the Settings backdrop previews while the Background choice screen has focus on an
/// option. `nil` shows the stored setting.
@MainActor
@Observable
final class BackgroundPreview {
    var mode: BackgroundMode?
}

extension EnvironmentValues {
    @Entry var backgroundPreview: BackgroundPreview?
}

extension BackgroundMode {
    var label: String {
        switch self {
        case .gradient: "Gradient"
        case .photo: "Photo"
        case .auto: "Auto"
        }
    }

    var help: String {
        switch self {
        case .gradient: "A drifting sky in the colors of the weather outside."
        case .photo: "A softly blurred photo of skies like yours, day and night."
        case .auto: "A photo while the sun is up, the gradient at night and during storms."
        }
    }
}

struct BackgroundChoiceScreen: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.backgroundPreview) private var preview
    @FocusState private var focused: BackgroundMode?

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text("Background")
                    .font(Theme.Typeface.screenTitle)
                    .accessibilityAddTraits(.isHeader)
                SettingsHelpPane(text: (focused ?? model.settings.backgroundMode).help)
            }
            .frame(width: 620, alignment: .leading)
            List {
                ForEach(BackgroundMode.allCases, id: \.self) { mode in
                    Button {
                        model.settings.backgroundMode = mode
                        dismiss()
                    } label: {
                        HStack {
                            Text(mode.label)
                            Spacer()
                            if mode == model.settings.backgroundMode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .focused($focused, equals: mode)
                    .accessibilityIdentifier("settings.background.option.\(mode.rawValue)")
                }
            }
            .frame(width: 1000)
        }
        .padding(.vertical, Theme.Layout.marginVertical)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
        .defaultFocus($focused, model.settings.backgroundMode)
        .onChange(of: focused) { _, mode in
            if let mode { preview?.mode = mode }
        }
        .onDisappear { preview?.mode = nil }
    }
}
