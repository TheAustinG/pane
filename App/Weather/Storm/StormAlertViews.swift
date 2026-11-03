import PaneCore
import SwiftUI

extension WeatherAlertInfo {
    var meta: String {
        [source, region].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Every active alert with a large QR code, over the takeover. Each row is a button so focus has
/// somewhere to rest and the list scrolls with the remote; selecting one closes the overlay.
struct StormAlertDetail: View {
    let alerts: [WeatherAlertInfo]
    let markImageData: Data?
    var focus: FocusState<StormFocus?>.Binding
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack {
                    PaneHeading(text: alerts.count == 1 ? "Weather alert" : "Weather alerts")
                    Spacer()
                    AppleWeatherMark(imageData: markImageData)
                }
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
