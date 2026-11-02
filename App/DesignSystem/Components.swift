import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct WeatherGlyph: View {
    let symbol: String
    var size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: size * 0.8, weight: .light))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PrecipChance: View {
    let percent: Int?

    var body: some View {
        Text(percent.map { "\($0)%" } ?? " ")
            .font(Theme.Typeface.caption.monospacedDigit())
            .foregroundStyle(Theme.Signal.rain)
            .frame(height: 26)
    }
}

enum Tone {
    case nudge
    case warning

    var ink: Color {
        switch self {
        case .nudge: Theme.Signal.nudgeInk
        case .warning: Theme.Signal.warning
        }
    }

    var accent: Color {
        switch self {
        case .nudge: Theme.Signal.nudge
        case .warning: Theme.Signal.warning
        }
    }

    var fill: Color {
        switch self {
        case .nudge: Theme.Signal.nudgeFill
        case .warning: Theme.Signal.warningFill
        }
    }

    var stroke: Color {
        switch self {
        case .nudge: Theme.Signal.nudgeStroke
        case .warning: Theme.Signal.warningStroke
        }
    }
}

struct NudgeChip: View {
    let text: String
    var symbol: String?
    var tone: Tone = .nudge

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(tone.accent)
            }
            Text(text).foregroundStyle(tone.ink)
        }
        .font(Theme.Typeface.label)
        .lineLimit(2)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: Theme.Glass.chipRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Glass.chipRadius, style: .continuous)
                .strokeBorder(tone.stroke, lineWidth: 1)
        }
    }
}

struct StatusRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .frame(width: Theme.Layout.iconWell, height: Theme.Layout.iconWell)
                .background(Theme.Ink.well, in: Circle())
                .accessibilityHidden(true)
                .padding(.trailing, Theme.Space.m)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.Typeface.bodyStrong)
                if let detail {
                    Text(detail)
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Ink.secondary)
                }
            }
            .lineLimit(1)
            .layoutPriority(1)
            Spacer(minLength: Theme.Space.s)
            trailing
        }
    }
}

extension StatusRow where Trailing == EmptyView {
    init(symbol: String, title: String, detail: String? = nil) {
        self.init(symbol: symbol, title: title, detail: detail) { EmptyView() }
    }
}

struct StaleNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "clock.arrow.circlepath")
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Ink.secondary)
    }
}

/// Weather alert. `message` is shown exactly as issued; when it does not fit, the full text lives
/// behind the QR code rather than being shortened here.
struct AlertBanner: View {
    let tone: Tone
    let title: String
    let meta: String
    var message: String?
    var qrURL: URL?
    /// Puts the message under the title row at full width, for narrow columns.
    var stacked = false

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(alignment: .top, spacing: Theme.Space.l) {
                        header
                        Spacer(minLength: 0)
                        if let qrURL { qr(qrURL) }
                    }
                    messageText
                }
            } else {
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        header
                        messageText
                    }
                    Spacer(minLength: 0)
                    if let qrURL { qr(qrURL) }
                }
            }
        }
        .padding(Theme.Space.l)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(tone.stroke, lineWidth: 1.5)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(tone.accent)
            }
            .font(Theme.Typeface.title)
            Text(meta)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var messageText: some View {
        if let message {
            Text(message)
                .font(Theme.Typeface.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func qr(_ url: URL) -> some View {
        VStack(spacing: Theme.Space.xxs) {
            QRCodeView(url: url, side: stacked ? 104 : 132)
            Text("Details")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
        }
    }
}

struct QRCodeView: View {
    let url: URL
    var side: CGFloat = 200

    var body: some View {
        Group {
            if let image = Self.render(url.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.white
            }
        }
        .frame(width: side, height: side)
        .padding(side * 0.08)
        .background(Color.white, in: RoundedRectangle(cornerRadius: side * 0.1, style: .continuous))
        .accessibilityLabel("QR code for \(url.host() ?? url.absoluteString)")
    }

    private static func render(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Sunrise-to-sunset arc. `fraction` is 0 at sunrise and 1 at sunset; outside that range the sun
/// dot is hidden and only the dashed path shows.
struct DaylightArc: View {
    let fraction: Double?
    let sunrise: String
    let sunset: String
    var caption: String?

    var body: some View {
        VStack(spacing: Theme.Space.xxs) {
            Canvas { context, size in
                let baseline = size.height - 6
                let start = CGPoint(x: 16, y: baseline)
                let end = CGPoint(x: size.width - 16, y: baseline)
                let control = CGPoint(x: size.width / 2, y: baseline - size.height * 1.55)
                var arc = Path()
                arc.move(to: start)
                arc.addQuadCurve(to: end, control: control)
                context.stroke(
                    arc,
                    with: .color(.white.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 8])
                )
                var line = Path()
                line.move(to: CGPoint(x: 0, y: baseline))
                line.addLine(to: CGPoint(x: size.width, y: baseline))
                context.stroke(line, with: .color(.white.opacity(0.3)), lineWidth: 1.5)
                if let fraction, (0...1).contains(fraction) {
                    let t = CGFloat(fraction)
                    let x = (1 - t) * (1 - t) * start.x + 2 * (1 - t) * t * control.x + t * t * end.x
                    let y = (1 - t) * (1 - t) * start.y + 2 * (1 - t) * t * control.y + t * t * end.y
                    let glow = CGRect(x: x - 22, y: y - 22, width: 44, height: 44)
                    context.fill(Path(ellipseIn: glow), with: .color(Theme.Signal.sun.opacity(0.25)))
                    let core = CGRect(x: x - 9, y: y - 9, width: 18, height: 18)
                    context.fill(Path(ellipseIn: core), with: .color(Theme.Signal.sun))
                }
            }
            .frame(height: 80)
            HStack {
                Label(sunrise, systemImage: "sunrise")
                Spacer(minLength: Theme.Space.s)
                if let caption { Text(caption) }
                Spacer(minLength: Theme.Space.s)
                Label(sunset, systemImage: "sunset")
            }
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Ink.secondary)
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Contribution grid: 26 weeks by 7 days, oldest column first. Levels are 0 (none) to 4, and -1
/// marks days after today.
struct ContributionGrid: View {
    let levels: [Int]
    let accent: Color
    var cell: CGFloat = 12
    var gap: CGFloat = 3

    private static let alphas: [Double] = [0, 0.28, 0.48, 0.72, 0.96]

    var body: some View {
        Canvas { context, _ in
            for (index, level) in levels.enumerated() where level >= 0 {
                let column = index / 7
                let row = index % 7
                let rect = CGRect(
                    x: CGFloat(column) * (cell + gap),
                    y: CGFloat(row) * (cell + gap),
                    width: cell,
                    height: cell
                )
                let color = level == 0 ? Theme.Ink.faint : accent.opacity(Self.alphas[min(level, 4)])
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color))
            }
        }
        .frame(width: 26 * (cell + gap) - gap, height: 7 * (cell + gap) - gap)
        .accessibilityLabel("Contribution graph, last 26 weeks")
    }
}
