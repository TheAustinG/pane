import Observation
import SwiftUI

/// The text the Settings help pane shows. `SettingsRoot` installs one in the environment; a row
/// outside it finds none and does nothing.
@MainActor
@Observable
final class SettingsHelpState {
    private(set) var text: String?
    private var owner: UUID?

    func focus(_ owner: UUID, text: String) {
        self.owner = owner
        self.text = text
    }

    func blur(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        text = nil
    }
}

extension EnvironmentValues {
    @Entry var settingsHelp: SettingsHelpState?
}

private struct SettingsHelpModifier: ViewModifier {
    let text: String
    @Environment(\.settingsHelp) private var help
    @FocusState private var isFocused: Bool
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused { help?.focus(owner, text: text) } else { help?.blur(owner) }
            }
            .onChange(of: text) { _, text in
                if isFocused { help?.focus(owner, text: text) }
            }
    }
}

extension View {
    /// Shows `text` in the Settings help pane while this row has focus.
    func settingsHelp(_ text: String) -> some View {
        modifier(SettingsHelpModifier(text: text))
    }
}

/// A row that shows a value and runs `action` when selected.
struct SettingsValueRow: View {
    let title: String
    let value: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LabeledContent(title, value: value)
        }
        .settingsHelp(help)
    }
}

/// The glass pane that explains the focused row.
struct SettingsHelpPane: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Layout.paneInset)
            .frame(width: 620, alignment: .leading)
            .glassPane()
            .animation(Theme.Motion.state, value: text)
            .accessibilityIdentifier("settings.help")
    }
}

/// A row that shows the chosen value and opens a list of choices. `Picker` cannot be used here:
/// its tvOS menu and navigation styles both draw outside the Settings look.
struct SettingsChoiceRow<Value: Hashable>: View {
    let title: String
    let help: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        NavigationLink {
            SettingsChoiceList(title: title, help: help, options: options, selection: $selection, label: label)
        } label: {
            LabeledContent(title, value: label(selection))
        }
        .settingsHelp(help)
    }
}

private struct SettingsChoiceList<Value: Hashable>: View {
    let title: String
    let help: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Value?

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(title)
                    .font(Theme.Typeface.screenTitle)
                    .accessibilityAddTraits(.isHeader)
                SettingsHelpPane(text: help)
            }
            .frame(width: 620, alignment: .leading)
            List {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                        dismiss()
                    } label: {
                        HStack {
                            Text(label(option))
                            Spacer()
                            if option == selection {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .focused($focused, equals: option)
                    .accessibilityIdentifier("settings.choice.\(label(option))")
                }
            }
            .frame(width: 1000)
        }
        .padding(.vertical, Theme.Layout.marginVertical)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
        .defaultFocus($focused, selection)
    }
}
