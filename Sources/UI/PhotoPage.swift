import FossifyCommons
import Photos
import SwiftUI
import UIKit

/// PhotoFragment: a zoomable image (SubsamplingScaleImageView / GestureImageView stand-in on UIScrollView).
struct PhotoPage: View {
    @Environment(Config.self) private var config
    let medium: Medium
    /// Display-only rotation from the rotate menu / gestures (degrees, multiple of 90).
    @Binding var rotation: Int
    let onTap: (CGPoint, CGSize) -> Void
    let onZoomChange: (Bool) -> Void
    @State private var image: UIImage?
    @State private var shown: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = shown {
                    ZoomableImage(image: image, rotation: $rotation, deepZoom: config.allowZoomingImages,
                                  oneToOne: config.allowOneToOneZoom, rotateGestures: config.allowRotatingWithGestures,
                                  hdr: config.ultraHdrRendering,
                                  onTap: { onTap($0, geo.size) }, onZoomChange: onZoomChange)
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.orange)
                        Text("Failed to load media.").foregroundStyle(.white)
                    }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: "\(medium.id)-\(medium.modified.timeIntervalSince1970)-\(config.showHighestQuality)") { await load(geo.size) }
            .onChange(of: image) { _, _ in updateShown() }
            .onChange(of: rotation) { _, _ in updateShown() }
        }
    }

    private func updateShown() {
        guard let image else { shown = nil; return }
        shown = rotation == 0 || image.images != nil ? image : (image.rotated(degrees: rotation) ?? image)
    }

    private func load(_ size: CGSize) async {
        if medium.isGif, let data = await ImageLoader.data(for: medium.asset) {
            image = ImageLoader.animatedImage(data)
            failed = image == nil
            return
        }
        let scale = UIScreen.main.scale
        let target = config.showHighestQuality ? PHImageManagerMaximumSize : CGSize(width: size.width * scale * 2, height: size.height * scale * 2)
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = true
        o.deliveryMode = config.fileLoadingPriority == .speed ? .opportunistic : .highQualityFormat
        o.version = .current
        let stream = AsyncStream<(UIImage?, Bool)> { cont in
            let id = PHImageManager.default().requestImage(for: medium.asset, targetSize: target, contentMode: .aspectFit, options: o) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                cont.yield((img, degraded))
                if !degraded { cont.finish() }
            }
            cont.onTermination = { _ in PHImageManager.default().cancelImageRequest(id) }
        }
        for await (img, degraded) in stream {
            if Task.isCancelled { return }
            if let img { image = img } else if !degraded && image == nil { failed = true }
        }
    }
}

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    @Binding var rotation: Int
    let deepZoom: Bool
    let oneToOne: Bool
    let rotateGestures: Bool
    let hdr: Bool
    let onTap: (CGPoint) -> Void
    let onZoomChange: (Bool) -> Void

    func makeUIView(context: Context) -> ZoomScrollView {
        let v = ZoomScrollView()
        v.coordinator = context.coordinator
        v.delegate = context.coordinator
        v.showsVerticalScrollIndicator = false
        v.showsHorizontalScrollIndicator = false
        v.contentInsetAdjustmentBehavior = .never
        v.decelerationRate = .fast
        v.backgroundColor = .clear
        v.imageView.contentMode = .scaleAspectFit
        v.addSubview(v.imageView)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        v.addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: doubleTap)
        v.addGestureRecognizer(tap)
        let rotate = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.rotate(_:)))
        rotate.delegate = context.coordinator
        v.addGestureRecognizer(rotate)
        context.coordinator.rotateGesture = rotate
        return v
    }

    func updateUIView(_ v: ZoomScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.rotateGesture?.isEnabled = rotateGestures
        v.imageView.preferredImageDynamicRange = hdr ? .high : .standard
        if v.deepZoom != deepZoom {
            v.deepZoom = deepZoom
            v.resetZoom()
        }
        if v.imageView.image !== image {
            v.imageView.image = image
            v.resetZoom()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomableImage
        weak var rotateGesture: UIRotationGestureRecognizer?
        private var doubleTapCount = 0

        init(_ parent: ZoomableImage) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? ZoomScrollView)?.imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerImage()
            parent.onZoomChange(scrollView.zoomScale > scrollView.minimumZoomScale + 0.01)
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            parent.onTap(g.location(in: g.view?.superview ?? g.view))
        }

        /// Double tap zooms in to fill the screen; with "Allow 1:1 zooming" a second double tap goes to 100%.
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let v = g.view as? ZoomScrollView else { return }
            let point = g.location(in: v.imageView)
            if v.zoomScale > v.minimumZoomScale + 0.01 {
                if parent.oneToOne && doubleTapCount == 1 && v.oneToOneScale > v.zoomScale + 0.01 {
                    doubleTapCount = 2
                    v.zoom(to: zoomRect(v, point, v.oneToOneScale), animated: true)
                } else {
                    doubleTapCount = 0
                    v.setZoomScale(v.minimumZoomScale, animated: true)
                }
            } else {
                doubleTapCount = 1
                v.zoom(to: zoomRect(v, point, min(max(v.fillScale, v.minimumZoomScale * 2), v.maximumZoomScale)), animated: true)
            }
        }

        private func zoomRect(_ v: UIScrollView, _ point: CGPoint, _ scale: CGFloat) -> CGRect {
            let size = CGSize(width: v.bounds.width / scale, height: v.bounds.height / scale)
            return CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        }

        /// allowRotatingWithGestures: snaps to the nearest 90 degrees when released.
        @objc func rotate(_ g: UIRotationGestureRecognizer) {
            guard let v = g.view as? ZoomScrollView else { return }
            switch g.state {
            case .changed:
                v.transform = CGAffineTransform(rotationAngle: g.rotation)
            case .ended, .cancelled:
                let steps = Int((g.rotation / (.pi / 2)).rounded())
                v.transform = .identity
                if steps != 0 { parent.rotation = ((parent.rotation + steps * 90) % 360 + 360) % 360 }
            default: break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            g is UIRotationGestureRecognizer && other is UIPinchGestureRecognizer
        }
    }
}

final class ZoomScrollView: UIScrollView {
    let imageView = UIImageView()
    weak var coordinator: ZoomableImage.Coordinator?
    /// "Allow deep zooming images": zoom well past 1:1 instead of stopping at about 3x the fitted size.
    var deepZoom = true
    private var lastSize: CGSize = .zero
    private(set) var fillScale: CGFloat = 1
    private(set) var oneToOneScale: CGFloat = 1

    private var imageSize: CGSize {
        guard let img = imageView.image else { return .zero }
        return CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize {
            lastSize = bounds.size
            resetZoom()
        }
        centerImage()
    }

    func resetZoom() {
        let size = imageSize
        guard size.width > 0, bounds.width > 0 else { return }
        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        let fit = min(bounds.width / size.width, bounds.height / size.height)
        fillScale = max(bounds.width / size.width, bounds.height / size.height)
        oneToOneScale = 1 / UIScreen.main.scale
        minimumZoomScale = fit
        maximumZoomScale = deepZoom ? max(fit * 8, oneToOneScale * 4) : max(fit * 3, oneToOneScale)
        zoomScale = fit
        centerImage()
    }

    func centerImage() {
        let w = contentSize.width, h = contentSize.height
        let insetX = max((bounds.width - w) / 2, 0)
        let insetY = max((bounds.height - h) / 2, 0)
        contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }
}
