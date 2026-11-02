#if DEBUG
import Observation
import QuartzCore
import SwiftUI
import UIKit

@MainActor
@Observable
final class FrameMeter {
    struct Stats: Equatable {
        var fps = 0.0
        var medianMs = 0.0
        var p95Ms = 0.0
        var droppedWindow = 0
        var droppedTotal = 0
        var maxFPS = 0
    }

    private static let windowSeconds = 5.0

    private(set) var stats = Stats()

    @ObservationIgnored private var window: [(t: CFTimeInterval, dt: Double)] = []
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var lastPublish: CFTimeInterval = 0
    @ObservationIgnored private var droppedTotal = 0
    @ObservationIgnored private var maxFPS = 0
    @ObservationIgnored private var targetInterval = 1.0 / 60

    func frame(timestamp: CFTimeInterval, targetTimestamp: CFTimeInterval, screenMaxFPS: Int) {
        guard let previous = lastTimestamp else {
            lastTimestamp = timestamp
            lastPublish = timestamp
            maxFPS = screenMaxFPS
            let linkInterval = targetTimestamp - timestamp
            targetInterval = screenMaxFPS > 0 ? 1.0 / Double(screenMaxFPS) : (linkInterval > 0 ? linkInterval : 1.0 / 60)
            return
        }
        lastTimestamp = timestamp
        let dt = timestamp - previous
        guard dt > 0 else { return }

        window.append((timestamp, dt))
        while let first = window.first, timestamp - first.t > Self.windowSeconds {
            window.removeFirst()
        }
        if dt > targetInterval * 1.5 { droppedTotal += 1 }
        if timestamp - lastPublish >= 0.5 {
            lastPublish = timestamp
            publish(now: timestamp)
        }
    }

    private func publish(now: CFTimeInterval) {
        let intervals = window.map(\.dt).sorted()
        var next = stats
        next.fps = Double(window.reduce(0) { $0 + (now - $1.t < 1.0 ? 1 : 0) })
        next.medianMs = Self.percentile(intervals, 0.5) * 1000
        next.p95Ms = Self.percentile(intervals, 0.95) * 1000
        next.droppedWindow = window.reduce(0) { $0 + ($1.dt > targetInterval * 1.5 ? 1 : 0) }
        next.droppedTotal = droppedTotal
        next.maxFPS = maxFPS
        stats = next
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[index]
    }
}

struct FrameMeterHost: UIViewRepresentable {
    let meter: FrameMeter

    func makeUIView(context: Context) -> DisplayLinkView {
        let view = DisplayLinkView()
        view.onFrame = { [meter] timestamp, target, maxFPS in
            meter.frame(timestamp: timestamp, targetTimestamp: target, screenMaxFPS: maxFPS)
        }
        return view
    }

    func updateUIView(_ view: DisplayLinkView, context: Context) {}

    static func dismantleUIView(_ view: DisplayLinkView, coordinator: ()) {
        view.stop()
    }
}

final class DisplayLinkView: UIView {
    var onFrame: (@MainActor (CFTimeInterval, CFTimeInterval, Int) -> Void)?
    private var link: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stop()
        guard window != nil else { return }
        // CADisplayLink retains its target, so a weak trampoline keeps this view releasable.
        let link = CADisplayLink(target: DisplayLinkTrampoline(self), selector: #selector(DisplayLinkTrampoline.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let maxFPS = window?.windowScene?.screen.maximumFramesPerSecond ?? 0
        MainActor.assumeIsolated {
            onFrame?(link.timestamp, link.targetTimestamp, maxFPS)
        }
    }
}

@MainActor
private final class DisplayLinkTrampoline: NSObject {
    weak var view: DisplayLinkView?

    init(_ view: DisplayLinkView) {
        self.view = view
    }

    @objc func tick(_ link: CADisplayLink) {
        view?.tick(link)
    }
}

/// Frame rate readout in the top right corner, driven by a display link while it is on screen.
struct FrameHUD: View {
    let quality: RenderQuality
    @State private var meter = FrameMeter()

    var body: some View {
        let stats = meter.stats
        VStack(alignment: .trailing, spacing: 1) {
            Text(String(format: "%3.0f fps  %.1f ms", stats.fps, stats.medianMs))
            Text(String(format: "p95 %.1f ms  drop %d/%d", stats.p95Ms, stats.droppedWindow, stats.droppedTotal))
            Text("quality \(quality.name)  max \(stats.maxFPS) Hz")
        }
        .font(.system(size: 18, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background { FrameMeterHost(meter: meter) }
        .accessibilityIdentifier("debug.fps.hud")
    }
}
#endif
