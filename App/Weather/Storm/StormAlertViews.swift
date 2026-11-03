import PaneCore
import SwiftUI

extension WeatherAlertInfo {
    var meta: String {
        [source, region].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// An alert as the takeover shows it: the summary exactly as issued, wrapped, with the issuer and a
/// QR code to Apple's alert page. It follows `AlertBanner`'s look; the identifiers are why it is
/// separate.
struct StormAlertBanner: View {
    let alert: WeatherAlertInfo
    let index: Int
    var meta: String
    var stacked = false

    private let tone = Tone.warning

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Label {
                    Text(alert.summary)
                        .accessibilityIdentifier("storm.alert.\(index).title")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(tone.accent)
                }
                .font(Theme.Typeface.title)
                Text(meta)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(spacing: Theme.Space.xxs) {
                QRCodeView(url: alert.detailsURL, side: stacked ? 104 : 132)
                    .accessibilityIdentifier("storm.alert.\(index).qr")
                Text("Details")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Ink.secondary)
            }
        }
        .padding(Theme.Space.l)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(tone.stroke, lineWidth: 1.5)
        }
    }
}

/// Every active alert with a large QR code, over the takeover. Each row is a button so focus has
/// somewhere to rest and the list scrolls with the remote; selecting one closes the overlay.
struct StormAlertDetail: View {
    let alerts: [WeatherAlertInfo]
    var focus: FocusState<StormFocus?>.Binding
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                PaneHeading(text: alerts.count == 1 ? "Weather alert" : "Weather alerts")
                ScrollView {
                    VStack(spacing: Theme.Layout.gutter) {
                        ForEach(Array(alerts.enumerated()), id: \.offset) { index, alert in
                            Button(action: close) { row(alert, index: index) }
                                .buttonStyle(GlassPaneButtonStyle())
                                .focused(focus, equals: .detail(index))
                                .accessibilityIdentifier("storm.alertDetail.\(index)")
                        }
                    }
                    .padding(.vertical, Theme.Space.l)
                }
                .scrollClipDisabled()
            }
            .frame(width: 1240)
            .padding(.vertical, Theme.Layout.marginVertical)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storm.alertDetail")
    }

    private func row(_ alert: WeatherAlertInfo, index: Int) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Label {
                    Text(alert.summary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tone.warning.accent)
                }
                .font(Theme.Typeface.title)
                Text(alert.meta)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Ink.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(spacing: Theme.Space.xs) {
                QRCodeView(url: alert.detailsURL, side: 220)
                    .accessibilityIdentifier("storm.alertDetail.qr.\(index)")
                Text("Scan for the full alert on Apple Weather")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Ink.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 260)
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
