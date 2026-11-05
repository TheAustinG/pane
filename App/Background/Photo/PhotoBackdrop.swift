import PaneCore
import SwiftUI
import UIKit

/// A photo filling the frame with its slow zoom, under the scrim that keeps the clock legible.
struct PhotoBackdrop: View {
    let photo: DecodedPhoto
    let zooms: Bool

    var body: some View {
        ZStack {
            ZoomingPhoto(photo: photo, zooms: zooms)
            PhotoScrim()
        }
    }
}

struct PhotoScrim: View {
    var body: some View {
        // CSS linear-gradient(115deg) end points on a 16:9 frame, so the fade runs at the same angle.
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.3), location: 0),
                .init(color: .black.opacity(0), location: 0.46),
            ],
            startPoint: UnitPoint(x: -0.0184, y: 0.0702),
            endPoint: UnitPoint(x: 1.0184, y: 0.9298)
        )
    }
}

/// Core Animation runs the zoom in the render server, so the 70 s legs cost the main thread nothing.
private struct ZoomingPhoto: UIViewRepresentable {
    let photo: DecodedPhoto
    let zooms: Bool

    func makeUIView(context: Context) -> ZoomingPhotoView {
        ZoomingPhotoView(image: photo.image)
    }

    func updateUIView(_ view: ZoomingPhotoView, context: Context) {
        view.setZooming(zooms)
    }
}

private final class ZoomingPhotoView: UIView {
    private static let zoomKey = "zoom"
    /// The mockup's drift while zooming in, as fractions of the frame.
    private static let drift = CGVector(dx: -0.015, dy: -0.01)

    private let imageLayer = CALayer()
    private var zoomedSize = CGSize.zero
    private var isZooming = true

    init(image: CGImage) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspectFill
        layer.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
        if bounds.size != zoomedSize { startZoom() }
    }

    /// Pauses in place rather than snapping back, so turning on Reduce Motion never jumps.
    func setZooming(_ zooms: Bool) {
        guard zooms != isZooming else { return }
        isZooming = zooms
        if zooms {
            let pausedAt = imageLayer.timeOffset
            imageLayer.speed = 1
            imageLayer.timeOffset = 0
            imageLayer.beginTime = 0
            imageLayer.beginTime = imageLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        } else {
            let now = imageLayer.convertTime(CACurrentMediaTime(), from: nil)
            imageLayer.speed = 0
            imageLayer.timeOffset = now
        }
    }

    private func startZoom() {
        zoomedSize = bounds.size
        imageLayer.removeAnimation(forKey: Self.zoomKey)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = CGFloat(Theme.Motion.photoZoomScale)
        let shift = CATransform3DMakeTranslation(Self.drift.dx * bounds.width, Self.drift.dy * bounds.height, 0)
        let zoom = CABasicAnimation(keyPath: "transform")
        zoom.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        zoom.toValue = NSValue(caTransform3D: CATransform3DConcat(shift, CATransform3DMakeScale(scale, scale, 1)))
        zoom.duration = Theme.Motion.photoZoomSeconds
        zoom.autoreverses = true
        zoom.repeatCount = .infinity
        zoom.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        zoom.isRemovedOnCompletion = false
        imageLayer.add(zoom, forKey: Self.zoomKey)
    }
}
