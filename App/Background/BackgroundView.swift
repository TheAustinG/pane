import PaneCore
import SwiftUI

enum BackgroundTarget: Hashable {
    case gradient
    case photo(PhotoKey)

    var name: String {
        switch self {
        case .gradient: "gradient"
        case .photo(let key): key.name
        }
    }
}

/// The dashboard and Settings background: the gradient sky or a blurred photo, by
/// `BackgroundPolicy`, crossfading when either changes. The scene's particles and vignette lie
/// over both. A photo that fails to load shows the gradient instead.
struct BackgroundView: View {
    let kind: BackgroundKind
    let photo: PhotoKey
    let palette: ScenePalette
    let quality: RenderQuality
    var particlesEnabled = true
    /// Off while something opaque covers the sky, so it stops drawing every frame.
    var animates = true

    /// The newest is on top. A second one exists only while it fades in over the first, which
    /// then goes, so a fully shown photo has no gradient drawing under it and a fully shown
    /// gradient holds no photo.
    @State private var layers: [Layer]
    @State private var isFading = false
    @State private var transition: SceneTransition
    @State private var particleFadeEnd = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Once-a-minute time-of-day updates glide over a minute, so they chain into steady motion.
    private static let glideSeconds: TimeInterval = 60

    init(
        kind: BackgroundKind,
        photo: PhotoKey,
        palette: ScenePalette,
        quality: RenderQuality,
        particlesEnabled: Bool = true,
        animates: Bool = true
    ) {
        self.kind = kind
        self.photo = photo
        self.palette = palette
        self.quality = quality
        self.particlesEnabled = particlesEnabled
        self.animates = animates
        let shown = kind == .photo ? PhotoStore.cached(photo) : nil
        _layers = State(initialValue: [Layer(content: shown.map(Layer.Content.photo) ?? .gradient)])
        _transition = State(initialValue: SceneTransition(palette: palette))
    }

    private var target: BackgroundTarget {
        kind == .photo ? .photo(photo) : .gradient
    }

    private var isPhotoSettled: Bool {
        !isFading && layers.count == 1 && layers[0].isPhoto && layers[0].target == target
    }

    var body: some View {
        ZStack {
            ForEach(layers) { layer in
                layerView(layer.content)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
            ParticleField(
                palette: particlesEnabled && animates ? transition.to : transition.to.withoutParticles,
                transitionEnd: max(transition.end, particleFadeEnd),
                particleCount: quality.particleCount,
                reduceMotion: reduceMotion
            )
            SkyVignette()
            if animates, layers.allSatisfy(\.isPhoto) {
                FrameTick()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay {
            ZStack {
                AccessibilityMarker(label: "Background", value: kind == .photo ? "photo \(photo.name)" : "gradient", id: "background.kind")
                AccessibilityMarker(label: "Background photo", value: isPhotoSettled ? "yes" : "no", id: "background.photoLoaded")
            }
        }
        .task(id: Step(target: target, isFading: isFading)) {
            await show(target)
        }
        .onChange(of: particlesEnabled && animates) {
            particleFadeEnd = .now.addingTimeInterval(Theme.Motion.nightDimSeconds)
        }
        .onChange(of: palette) { _, newPalette in
            transition.retarget(
                to: newPalette,
                at: .now,
                blendSeconds: Theme.Motion.sceneBlendSeconds,
                glideSeconds: Self.glideSeconds
            )
        }
    }

    @ViewBuilder
    private func layerView(_ content: Layer.Content) -> some View {
        switch content {
        case .gradient:
            SkyGradient(transition: transition, quality: quality, drifts: !reduceMotion && animates)
        case .photo(let photo):
            PhotoBackdrop(photo: photo, zooms: !reduceMotion && animates)
        }
    }

    /// Runs again when the target changes or a crossfade ends, so a change during a crossfade
    /// waits for it and only the current and incoming photos are ever decoded.
    private func show(_ target: BackgroundTarget) async {
        guard !isFading, layers.last?.target != target else { return }
        var content = Layer.Content.gradient
        if case .photo(let key) = target {
            let photo = await PhotoStore.load(key)
            guard !Task.isCancelled else { return }
            if let photo {
                content = .photo(photo)
            } else if layers.last?.target == .gradient {
                try? await Task.sleep(for: .seconds(PhotoStore.retryAfter))
                guard !Task.isCancelled else { return }
                return await show(target)
            }
        }
        guard layers.last?.target != content.target else { return }
        crossfade(to: Layer(content: content))
    }

    private func crossfade(to layer: Layer) {
        isFading = true
        withAnimation(.easeInOut(duration: Theme.Motion.photoCrossfadeSeconds)) {
            layers.append(layer)
        } completion: {
            layers = [layer]
            isFading = false
            #if DEBUG
            PhotoCycle.crossfadeEnded(to: layer.target)
            #endif
        }
    }

    private struct Step: Equatable {
        let target: BackgroundTarget
        let isFading: Bool
    }

    private struct Layer: Identifiable {
        enum Content {
            case gradient
            case photo(DecodedPhoto)

            var target: BackgroundTarget {
                switch self {
                case .gradient: .gradient
                case .photo(let photo): .photo(photo.key)
                }
            }
        }

        let id = UUID()
        let content: Content

        var target: BackgroundTarget { content.target }

        var isPhoto: Bool {
            if case .photo = content { true } else { false }
        }
    }
}

/// With no SwiftUI animation running, presenting Settings stalls the main thread inside SwiftUI's
/// update loop for up to 30 s on tvOS 27 (simulator and the A15). The gradient's drift always ticks
/// every frame; a photo does not, so this stands in for it at a fraction of the cost.
private struct FrameTick: View {
    var body: some View {
        TimelineView(.animation) { context in
            Color.white
                .opacity(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) < 1 ? 0.002 : 0.001)
                .frame(width: 1, height: 1)
        }
    }
}

/// An invisible element that exposes state to UI tests.
struct AccessibilityMarker: View {
    let label: String
    let value: String
    let id: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityIdentifier(id)
    }
}

private extension ScenePalette {
    var withoutParticles: ScenePalette {
        var palette = self
        palette.particleIntensity = 0
        return palette
    }
}
