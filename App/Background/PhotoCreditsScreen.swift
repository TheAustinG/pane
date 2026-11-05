import PaneCore
import SwiftUI

/// One row per shipped photo, with its credit line, license and a QR code to its source page.
struct PhotoCreditsScreen: View {
    private let credits = Self.loaded
    @FocusState private var focused: String?

    private static let loaded: [PhotoCredit] = {
        guard let url = Bundle.main.url(forResource: "photo-credits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? PhotoCredits.decode(data) else { return [] }
        let bySlot = Dictionary(decoded.photos.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
        return PhotoKey.all.compactMap { bySlot[$0.name] }
    }()

    static var summary: String {
        loaded.isEmpty ? "Unavailable" : "\(loaded.count) photos"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text("Photo credits")
                    .font(Theme.Typeface.screenTitle)
                    .accessibilityAddTraits(.isHeader)
                SettingsHelpPane(text: helpText, qrURL: focusedCredit?.sourcePage)
            }
            .frame(width: 620, alignment: .leading)
            List {
                if credits.isEmpty {
                    Button {} label: {
                        Text("Credits unavailable")
                    }
                    .accessibilityIdentifier("settings.credits.unavailable")
                } else {
                    ForEach(credits, id: \.slot) { credit in
                        Button {} label: {
                            LabeledContent(credit.label, value: credit.creator)
                        }
                        .focused($focused, equals: credit.slot)
                        .accessibilityIdentifier("settings.credits.\(credit.slot)")
                    }
                }
            }
            .frame(width: 1000)
        }
        .padding(.vertical, Theme.Layout.marginVertical)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
        .defaultFocus($focused, credits.first?.slot)
    }

    private var focusedCredit: PhotoCredit? {
        credits.first { $0.slot == focused }
    }

    private var helpText: String {
        guard let credit = focusedCredit else {
            return credits.isEmpty ? "The credits file is missing from this build." : "Choose a photo to see who took it."
        }
        var lines = [credit.title, credit.attribution]
        if !credit.attribution.contains(credit.license) { lines.append(credit.license) }
        if let licenseURL = credit.licenseURL { lines.append(licenseURL.absoluteString) }
        lines.append("Cropped, resized and blurred for Pane.")
        return lines.joined(separator: "\n")
    }
}

private extension PhotoCredit {
    var label: String {
        guard let key else { return slot }
        return "\(key.condition.label), \(key.time.rawValue)"
    }
}

private extension ConditionFamily {
    var label: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .cloudy: "Cloudy"
        case .rain: "Rain"
        case .storm: "Storm"
        case .snow: "Snow"
        case .fog: "Fog"
        }
    }
}
