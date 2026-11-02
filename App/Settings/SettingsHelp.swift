import Observation
import SwiftUI

/// The text the Settings help pane shows. `SettingsRoot` installs one in the environment; a row
/// outside it finds none and does nothing.
@MainActor
@Observable
final class SettingsHelpState {
    private(set) var text: String?
    /// A link the help pane shows as a QR code, since the TV cannot open links.
    private(set) var qrURL: URL?
    private var owner: UUID?

    func focus(_ owner: UUID, text: String, qrURL: URL? = nil) {
        self.owner = owner
        self.text = text
        self.qrURL = qrURL
    }

    func blur(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        text = nil
        qrURL = nil
    }
}

extension EnvironmentValues {
    @Entry var settingsHelp: SettingsHelpState?
}

private struct SettingsHelpModifier: ViewModifier {
    let text: String
    let qrURL: URL?
    @Environment(\.settingsHelp) private var help
    @FocusState private var isFocused: Bool
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused { help?.focus(owner, text: text, qrURL: qrURL) } else { help?.blur(owner) }
            }
            .onChange(of: text) { _, text in
                if isFocused { help?.focus(owner, text: text, qrURL: qrURL) }
            }
            .onChange(of: qrURL) { _, qrURL in
                if isFocused { help?.focus(owner, text: text, qrURL: qrURL) }
            }
    }
}

extension View {
    /// Shows `text`, and `qrURL` as a QR code, in the Settings help pane while this row has focus.
    func settingsHelp(_ text: String, qrURL: URL? = nil) -> some View {
        modifier(SettingsHelpModifier(text: text, qrURL: qrURL))
    }
}

/// A row that shows a value and runs `action` when selected.
struct SettingsValueRow: View {
    let title: String
    let value: String
    let help: String
    var qrURL: URL?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LabeledContent(title, value: value)
        }
        .settingsHelp(help, qrURL: qrURL)
    }
}

/// The glass pane that explains the focused row.
struct SettingsHelpPane: View {
    let text: String
    var qrURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(text)
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.help")
            if let qrURL {
                QRCodeView(url: qrURL, side: 220)
                    .accessibilityIdentifier("settings.help.qr")
            }
        }
        .padding(Theme.Layout.paneInset)
        .frame(width: 620, alignment: .leading)
        .glassPane()
        .animation(Theme.Motion.state, value: text)
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
