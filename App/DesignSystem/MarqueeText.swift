import SwiftUI

extension EnvironmentValues {
    /// Night dim and the storm takeover hold every marquee still, truncated at its start.
    @Entry var marqueePaused = false
}

/// One line that scrolls sideways when it is wider than its space: it holds at the start, slides
/// left until the copy behind it reaches the start, then holds again. Text that fits never moves.
/// Reduce Motion and `marqueePaused` show it truncated instead. Font and color come from the
/// environment, like `Text`.
struct MarqueeText: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.marqueePaused) private var paused
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    static let speed: CGFloat = 36
    static let hold: TimeInterval = 3
    static let gap: CGFloat = 56
    static let fade: CGFloat = 18

    var body: some View {
        let scrolls = textWidth > boxWidth + 1 && boxWidth > 0 && !reduceMotion && !paused
        Text(text)
            .lineLimit(1)
            .opacity(scrolls ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .background(alignment: .leading) {
                Text(text)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if scrolls {
                    HStack(spacing: Self.gap) {
                        Text(text).fixedSize()
                        Text(text).fixedSize()
                    }
                    .offset(x: offset)
                    .frame(width: boxWidth, alignment: .leading)
                    .clipped()
                    .mask(edgeFade(leading: offset < 0))
                    .accessibilityHidden(true)
                    .task(id: textWidth) { await loop() }
                }
            }
    }

    /// One linear animation per pass, so nothing redraws during the hold. At the end of a pass the
    /// second copy sits exactly where the first started, so the jump back to 0 is invisible.
    private func loop() async {
        let travel = textWidth + Self.gap
        let duration = Double(travel / Self.speed)
        var reset = Transaction()
        reset.disablesAnimations = true
        while !Task.isCancelled {
            withTransaction(reset) { offset = 0 }
            try? await Task.sleep(for: .seconds(Self.hold))
            guard !Task.isCancelled else { break }
            withAnimation(.linear(duration: duration)) { offset = -travel }
            try? await Task.sleep(for: .seconds(duration))
        }
        withTransaction(reset) { offset = 0 }
    }

    /// The leading edge fades only while moving, so the line reads cleanly while it holds.
    private func edgeFade(leading: Bool) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fade)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fade)
        }
    }
}
