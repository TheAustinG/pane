#if DEBUG
import MapKit
import SwiftUI

enum StormLayout: String {
    case side
    case bottom
}

/// Storm takeover in both strip layouts. The map is real MapKit over a sample location; the radar
/// echoes are drawn here as a stand-in for the tile renderer.
struct StormSample: View {
    let scene: ScenePreset
    let layout: StormLayout
    var focus: FocusState<String?>.Binding

    private static let sampleRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.47, longitude: -97.52),
        span: MKCoordinateSpan(latitudeDelta: 2.6, longitudeDelta: 4.6)
    )

    private static let alertMessage = "At 7:12 PM, severe thunderstorms were located along a line from 10 miles west of the city to the county line, moving east at 35 mph. Hazards include 60 mph wind gusts and penny size hail. Expect damage to roofs, siding and trees."

    var body: some View {
        ZStack {
            Map(initialPosition: .region(Self.sampleRegion), interactionModes: [])
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .environment(\.colorScheme, .dark)
            SampleEchoes()
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            switch layout {
            case .side: sideLayout
            case .bottom: bottomLayout
            }
        }
        .ignoresSafeArea()
        .environment(\.glassShade, 0.28)
    }

    private var sideLayout: some View {
        HStack(alignment: .bottom, spacing: Theme.Layout.gutter) {
            RadarTimeline(current: 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: Theme.Layout.gutter) {
                conditions
                    .padding(Theme.Layout.paneInset)
                    .frame(width: Theme.Layout.stormColumnWidth, alignment: .leading)
                    .glassPane()
                Button {} label: {
                    AlertBanner(
                        tone: .warning,
                        title: "Severe Thunderstorm Warning",
                        meta: "National Weather Service, until 8:15 PM",
                        message: Self.alertMessage,
                        qrURL: URL(string: "https://weatherkit.apple.com/alertDetails/index.html"),
                        stacked: true
                    )
                    .padding(Theme.Space.s)
                    .frame(width: Theme.Layout.stormColumnWidth)
                }
                .buttonStyle(GlassPaneButtonStyle())
                .focused(focus, equals: "alert")
                .accessibilityIdentifier("preview.storm.alert")
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Theme.Layout.marginVertical)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
    }

    private var bottomLayout: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.gutter) {
            Spacer(minLength: 0)
            RadarTimeline(current: 9)
                .frame(width: 900)
            HStack(spacing: 0) {
                conditions
                    .frame(width: 470, alignment: .leading)
                Divider().overlay(Theme.Ink.rule).padding(.vertical, Theme.Space.s)
                Button {} label: {
                    AlertBanner(
                        tone: .warning,
                        title: "Severe Thunderstorm Warning",
                        meta: "National Weather Service, until 8:15 PM. Click for the full alert.",
                        qrURL: URL(string: "https://weatherkit.apple.com/alertDetails/index.html")
                    )
                    .frame(width: 830)
                }
                .buttonStyle(GlassPaneButtonStyle())
                .focused(focus, equals: "alert")
                .padding(.horizontal, Theme.Space.l)
                .accessibilityIdentifier("preview.storm.alert")
                Divider().overlay(Theme.Ink.rule).padding(.vertical, Theme.Space.s)
                compactHome
                    .padding(.leading, Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.Layout.paneInset)
            .frame(height: Theme.Layout.stormStripHeight)
            .glassPane()
        }
        .padding(.vertical, Theme.Layout.marginVertical)
        .padding(.horizontal, Theme.Layout.marginHorizontal)
    }

    private var conditions: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ClockBlock(scene: scene, compact: true)
            HStack(spacing: Theme.Space.m) {
                WeatherGlyph(symbol: scene.symbol, size: 64)
                Text(scene.temp).font(.system(size: 72, weight: .thin))
                VStack(alignment: .leading, spacing: 0) {
                    Text(scene.condition).font(Theme.Typeface.bodyStrong)
                    Text("H \(scene.high)   L \(scene.low)")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Ink.secondary)
                }
                .lineLimit(1)
            }
            if layout == .side {
                Rectangle().fill(Theme.Ink.rule).frame(height: 1)
                HStack(spacing: Theme.Space.l) {
                    Label("Door locked", systemImage: "lock")
                    Label("3 lights on", systemImage: "lightbulb")
                    Spacer(minLength: 0)
                    WeatherMarkPlaceholder()
                }
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
            }
        }
    }

    private var compactHome: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            StatusRow(symbol: "lock", title: "Door locked")
            StatusRow(symbol: "lightbulb", title: "3 lights on")
        }
    }
}

struct RadarTimeline: View {
    let current: Int
    var frames = 12

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .semibold))
            Text("7:05 PM")
                .font(Theme.Typeface.bodyStrong.monospacedDigit())
            HStack(spacing: 8) {
                ForEach(0..<frames, id: \.self) { index in
                    Capsule()
                        .fill(index == current ? Theme.Ink.primary : (index < current ? Theme.Ink.secondary : Theme.Ink.rule))
                        .frame(width: index == current ? 28 : 18, height: 8)
                }
            }
            Text("Now")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.secondary)
            Text("Sample radar")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .glassPane()
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

private struct SampleEchoes: View {
    private static let ramp: [UInt32] = [0x3FB45A, 0x2E8F45, 0xF0D23A, 0xF08A26, 0xD9402C]

    var body: some View {
        Canvas { context, size in
            context.addFilter(.blur(radius: 18))
            let cells: [(CGFloat, CGFloat, CGFloat, CGFloat, Int)] = [
                (0.18, 0.30, 0.20, 0.55, 0), (0.24, 0.38, 0.13, 0.36, 1), (0.27, 0.45, 0.07, 0.18, 2),
                (0.29, 0.48, 0.035, 0.08, 3), (0.30, 0.50, 0.015, 0.035, 4),
                (0.40, 0.18, 0.16, 0.30, 0), (0.43, 0.24, 0.08, 0.16, 1), (0.45, 0.27, 0.035, 0.07, 2),
                (0.10, 0.62, 0.14, 0.26, 0), (0.13, 0.68, 0.06, 0.12, 1),
                (0.52, 0.58, 0.10, 0.22, 0), (0.55, 0.63, 0.045, 0.09, 2),
            ]
            for (x, y, w, h, level) in cells {
                let rect = CGRect(
                    x: size.width * (x - w / 2),
                    y: size.height * (y - h / 2),
                    width: size.width * w,
                    height: size.height * h
                )
                context.fill(Path(ellipseIn: rect), with: .color(Color(hex: Self.ramp[level]).opacity(0.62)))
            }
        }
        .allowsHitTesting(false)
    }
}
#endif
