import CoreImage
import CoreImage.CIFilterBuiltins
import FossifyCommons
import Photos
import PencilKit
import SwiftUI
import UIKit

/// EditActivity: crop / rotate / flip, filters and drawing, saved as a copy or over the original.
struct EditorView: View {
    @Environment(MediaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let id: String

    enum Mode { case none, filter, crop, draw }

    @State private var medium: Medium?
    @State private var source: CIImage?
    @State private var mode: Mode = .none
    @State private var rotation = 0
    @State private var flipH = false
    @State private var flipV = false
    @State private var filter = EditorFilter.none
    /// Normalized crop rect in the transformed image.
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var aspect: CGFloat?
    @State private var aspectChoice = 0
    @State private var canvas = PKCanvasView()
    @State private var canvasSize: CGSize = .zero
    @State private var drawColor = Color.white
    @State private var brushSize: Double = 20
    @State private var preview: UIImage?
    @State private var thumbs: [EditorFilter: UIImage] = [:]
    @State private var showSave = false
    @State private var showOtherRatio = false
    @State private var share: ShareItems?
    @State private var saving = false

    private let context = CIContext()

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Editor", background: .black, tint: .white) {
                IconButton(icon: "square.and.arrow.up") { shareResult() }
                IconButton(icon: "checkmark") { showSave = true }
            }
            GeometryReader { geo in
                ZStack {
                    if let preview {
                        let fitted = fit(preview.size, in: geo.size)
                        Image(uiImage: preview)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .overlay {
                                if mode == .crop {
                                    CropOverlay(rect: $crop, aspect: aspect, imageSize: preview.size)
                                }
                            }
                            .overlay {
                                if mode != .crop {
                                    CanvasRepresentable(canvas: canvas, enabled: mode == .draw, color: UIColor(drawColor), width: brushSize)
                                        .onAppear { canvasSize = fitted }
                                        .onChange(of: fitted) { _, s in canvasSize = s }
                                }
                            }
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding(12)
            modeActions
            primaryActions
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .statusBarHidden()
        .task { await load() }
        .onChange(of: rotation) { _, _ in resetCrop(); render() }
        .onChange(of: flipH) { _, _ in render() }
        .onChange(of: flipV) { _, _ in render() }
        .onChange(of: filter) { _, _ in render() }
        .onChange(of: mode) { _, _ in render() }
        .confirmationDialog("Save as", isPresented: $showSave) {
            Button("Save as a new file") { save(overwrite: false) }
            if medium?.asset.canPerform(.content) == true {
                Button("Overwrite original") { save(overwrite: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showOtherRatio) {
            OtherAspectRatioDialog { x, y in
                config.lastEditorCropOtherAspectRatioX = x
                config.lastEditorCropOtherAspectRatioY = y
                setAspect(4)
            }
        }
        .sheet(item: $share) { ShareSheet(items: $0.urls) }
    }

    // MARK: Bottom bars

    @ViewBuilder
    private var modeActions: some View {
        switch mode {
        case .filter:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EditorFilter.allCases, id: \.self) { f in
                        Button { filter = f } label: {
                            VStack(spacing: 4) {
                                Group {
                                    if let t = thumbs[f] { Image(uiImage: t).resizable().scaledToFill() } else { Color.gray }
                                }
                                .frame(width: 64, height: 64)
                                .clipped()
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(f == filter ? palette.primaryColor : .clear, lineWidth: 3))
                                Text(f.title).font(.system(size: 12))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 96)
        case .crop:
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    IconButton(icon: "rotate.right") { rotation = (rotation + 90) % 360 }
                    IconButton(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right") { flipH.toggle() }
                    IconButton(icon: "arrow.up.and.down.righttriangle.up.righttriangle.down") { flipV.toggle() }
                    Spacer()
                    IconButton(icon: "arrow.counterclockwise") { resetCrop() }
                }
                HStack(spacing: 0) {
                    ForEach([(0, "Free"), (1, "1:1"), (2, "4:3"), (3, "16:9"), (4, "Other")], id: \.0) { item in
                        Button {
                            if item.0 == 4 { showOtherRatio = true } else { setAspect(item.0) }
                        } label: {
                            Text(item.1)
                                .font(.system(size: 15, weight: aspectChoice == item.0 ? .bold : .regular))
                                .foregroundStyle(aspectChoice == item.0 ? palette.primaryColor : .white)
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        case .draw:
            HStack(spacing: 12) {
                ColorPicker("", selection: $drawColor, supportsOpacity: false).labelsHidden()
                Slider(value: $brushSize, in: 2...100).tint(palette.primaryColor)
                IconButton(icon: "arrow.uturn.backward") { canvas.undoManager?.undo() }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
        case .none:
            EmptyView()
        }
    }

    /// bottom_editor_primary_actions.
    private var primaryActions: some View {
        HStack(spacing: 0) {
            modeButton(.filter, "camera.filters", "Filter")
            modeButton(.crop, "crop.rotate", "Crop")
            modeButton(.draw, "paintbrush.pointed", "Draw")
        }
        .padding(.vertical, 8)
    }

    private func modeButton(_ m: Mode, _ icon: String, _ title: String) -> some View {
        Button {
            if m == .draw && mode == .crop { canvas.drawing = PKDrawing() }
            mode = mode == m ? .none : m
            if m == .filter && thumbs.isEmpty { makeThumbs() }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title).font(.system(size: 12))
            }
            .foregroundStyle(mode == m ? palette.primaryColor : .white)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Pipeline

    private func load() async {
        let o = PHFetchOptionsFactory.all()
        guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: o).firstObject else { return }
        medium = Medium(asset: a, info: store.fileInfo[id], folderName: "")
        guard let image = await ImageLoader.image(for: a, size: CGSize(width: 4096, height: 4096)) else {
            store.toast = "Invalid image path"
            router.pop()
            return
        }
        source = CIImage(image: image)?.oriented(forExifOrientation: exif(image.imageOrientation))
        let r = config.lastEditorCropAspectRatio
        setAspect(r == 4 ? 4 : r)
        render()
    }

    private func exif(_ o: UIImage.Orientation) -> Int32 {
        switch o {
        case .up: return 1
        case .down: return 3
        case .left: return 8
        case .right: return 6
        case .upMirrored: return 2
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .rightMirrored: return 7
        @unknown default: return 1
        }
    }

    /// Rotated, flipped and filtered (no crop).
    private func transformed(_ base: CIImage) -> CIImage {
        var img = base
        if flipH { img = img.oriented(.upMirrored) }
        if flipV { img = img.oriented(.downMirrored) }
        switch rotation {
        case 90: img = img.oriented(.right)
        case 180: img = img.oriented(.down)
        case 270: img = img.oriented(.left)
        default: break
        }
        img = filter.apply(img)
        return img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
    }

    private func cropped(_ img: CIImage) -> CIImage {
        let e = img.extent
        let r = CGRect(x: crop.minX * e.width, y: (1 - crop.maxY) * e.height, width: crop.width * e.width, height: crop.height * e.height)
        return img.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY))
    }

    private func render() {
        guard let source else { return }
        var img = transformed(source)
        if mode != .crop { img = cropped(img) }
        if let cg = context.createCGImage(img, from: img.extent) { preview = UIImage(cgImage: cg) }
    }

    private func makeThumbs() {
        guard let source else { return }
        let scale = 160 / max(source.extent.width, source.extent.height)
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        for f in EditorFilter.allCases {
            let out = f.apply(small)
            if let cg = context.createCGImage(out, from: small.extent) { thumbs[f] = UIImage(cgImage: cg) }
        }
    }

    private func fit(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let s = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * s, height: size.height * s)
    }

    // MARK: Crop

    private func setAspect(_ choice: Int) {
        aspectChoice = choice
        config.lastEditorCropAspectRatio = choice
        switch choice {
        case 1: aspect = 1
        case 2: aspect = 4.0 / 3
        case 3: aspect = 16.0 / 9
        case 4: aspect = config.lastEditorCropOtherAspectRatioX / max(config.lastEditorCropOtherAspectRatioY, 0.01)
        default: aspect = nil
        }
        resetCrop()
    }

    private func resetCrop() {
        guard let source else { return }
        let e = transformed(source).extent
        guard let aspect, e.width > 0 else {
            crop = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        // Largest centered rect with the aspect ratio, normalized.
        let imageAspect = e.width / e.height
        if aspect > imageAspect {
            let h = imageAspect / aspect
            crop = CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        } else {
            let w = aspect / imageAspect
            crop = CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        }
    }

    // MARK: Output

    private func output() -> Data? {
        guard let source else { return nil }
        let img = cropped(transformed(source))
        guard let cg = context.createCGImage(img, from: img.extent) else { return nil }
        var result = UIImage(cgImage: cg)
        if !canvas.drawing.strokes.isEmpty && canvasSize.width > 0 {
            let scale = result.size.width / canvasSize.width
            let drawing = canvas.drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            result = UIGraphicsImageRenderer(size: result.size, format: format).image { _ in
                result.draw(at: .zero)
                drawing.draw(in: CGRect(origin: .zero, size: result.size))
            }
        }
        if medium?.uti == "public.png" { return result.pngData() }
        return result.jpegData(compressionQuality: 0.95)
    }

    private func save(overwrite: Bool) {
        guard !saving, let medium, let data = output() else {
            store.toast = "Image editing failed"
            return
        }
        saving = true
        let done: (Bool) -> Void = { ok in
            saving = false
            if ok {
                store.toast = "Image edited successfully"
                router.pop()
            }
        }
        if overwrite {
            store.overwrite(medium.asset, with: data, description: "edit", completion: done)
        } else {
            store.saveNewImage(data, album: nil, completion: done)
        }
    }

    private func shareResult() {
        guard let data = output() else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = ((medium?.name ?? "image") as NSString).deletingPathExtension + (medium?.uti == "public.png" ? ".png" : ".jpg")
        let url = dir.appendingPathComponent(name)
        if (try? data.write(to: url)) != nil { share = ShareItems([url]) }
    }
}

/// The editor's filter presets (Core Image photo effects in place of the Android filter pack).
enum EditorFilter: String, CaseIterable {
    case none, chrome, fade, instant, mono, noir, process, tonal, transfer, sepia, vignette

    var title: String { self == .none ? "None" : rawValue.capitalized }

    func apply(_ img: CIImage) -> CIImage {
        let f: CIFilter
        switch self {
        case .none: return img
        case .chrome: f = CIFilter.photoEffectChrome()
        case .fade: f = CIFilter.photoEffectFade()
        case .instant: f = CIFilter.photoEffectInstant()
        case .mono: f = CIFilter.photoEffectMono()
        case .noir: f = CIFilter.photoEffectNoir()
        case .process: f = CIFilter.photoEffectProcess()
        case .tonal: f = CIFilter.photoEffectTonal()
        case .transfer: f = CIFilter.photoEffectTransfer()
        case .sepia:
            let s = CIFilter.sepiaTone()
            s.intensity = 0.9
            f = s
        case .vignette:
            let v = CIFilter.vignette()
            v.intensity = 1.5
            v.radius = 2
            f = v
        }
        f.setValue(img, forKey: kCIInputImageKey)
        return f.outputImage?.cropped(to: img.extent) ?? img
    }
}

/// CropImageView's frame: drag the corners or the whole frame; keeps the aspect ratio when set.
struct CropOverlay: View {
    @Binding var rect: CGRect
    let aspect: CGFloat?
    let imageSize: CGSize
    @State private var start: CGRect?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let r = CGRect(x: rect.minX * size.width, y: rect.minY * size.height, width: rect.width * size.width, height: rect.height * size.height)
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: size))
                    p.addRect(r)
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                Rectangle().stroke(Color.white, lineWidth: 2)
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { v in move(v.translation, size) }.onEnded { _ in start = nil })
                ForEach(0..<4, id: \.self) { corner in
                    Circle().fill(Color.white).frame(width: 22, height: 22)
                        .position(x: corner % 2 == 0 ? r.minX : r.maxX, y: corner < 2 ? r.minY : r.maxY)
                        .gesture(DragGesture().onChanged { v in resize(corner, v.translation, size) }.onEnded { _ in start = nil })
                }
            }
        }
    }

    private func move(_ t: CGSize, _ size: CGSize) {
        if start == nil { start = rect }
        guard let s = start else { return }
        var r = s.offsetBy(dx: t.width / size.width, dy: t.height / size.height)
        r.origin.x = min(max(r.minX, 0), 1 - r.width)
        r.origin.y = min(max(r.minY, 0), 1 - r.height)
        rect = r
    }

    private func resize(_ corner: Int, _ t: CGSize, _ size: CGSize) {
        if start == nil { start = rect }
        guard let s = start else { return }
        let dx = t.width / size.width, dy = t.height / size.height
        var minX = s.minX, minY = s.minY, maxX = s.maxX, maxY = s.maxY
        if corner % 2 == 0 { minX = min(max(s.minX + dx, 0), s.maxX - 0.05) } else { maxX = max(min(s.maxX + dx, 1), s.minX + 0.05) }
        if corner < 2 { minY = min(max(s.minY + dy, 0), s.maxY - 0.05) } else { maxY = max(min(s.maxY + dy, 1), s.minY + 0.05) }
        if let aspect, size.height > 0 {
            // Normalized aspect = pixel aspect corrected by the view's aspect.
            let a = aspect * size.height / size.width
            let w = maxX - minX
            var h = w / a
            if corner < 2 { minY = maxY - h } else { maxY = minY + h }
            if minY < 0 || maxY > 1 {
                h = corner < 2 ? maxY : 1 - minY
                let w2 = h * a
                if corner < 2 { minY = maxY - h } else { maxY = minY + h }
                if corner % 2 == 0 { minX = maxX - w2 } else { maxX = minX + w2 }
            }
        }
        rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// PencilKit canvas for the Draw mode.
struct CanvasRepresentable: UIViewRepresentable {
    let canvas: PKCanvasView
    let enabled: Bool
    let color: UIColor
    let width: Double

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        return canvas
    }

    func updateUIView(_ v: PKCanvasView, context: Context) {
        v.isUserInteractionEnabled = enabled
        v.tool = PKInkingTool(.marker, color: color, width: width)
    }
}

/// OtherAspectRatioDialog (+ CustomAspectRatioDialog).
struct OtherAspectRatioDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let onPick: (Double, Double) -> Void
    @State private var x = ""
    @State private var y = ""

    private let ratios: [(Double, Double)] = [(2, 1), (3, 2), (4, 3), (5, 3), (16, 9), (19, 9), (1, 2), (2, 3), (3, 4), (3, 5), (9, 16), (9, 19)]

    var body: some View {
        DialogFrame(title: nil) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2)) {
                ForEach(ratios, id: \.0.description) { r in
                    Button("\(Int(r.0)):\(Int(r.1))") {
                        onPick(r.0, r.1)
                        dismiss()
                    }
                    .foregroundStyle(palette.textColor)
                    .padding(.vertical, 10)
                }
            }
            Text("Custom").font(.system(size: 15, weight: .medium)).foregroundStyle(palette.primaryColor).padding(.top, 12)
            HStack {
                DialogTextField(placeholder: "Width", text: $x).keyboardType(.decimalPad)
                Text(":").foregroundStyle(palette.textColor)
                DialogTextField(placeholder: "Height", text: $y).keyboardType(.decimalPad)
            }
            DialogButtons(okEnabled: (Double(x) ?? 0) > 0 && (Double(y) ?? 0) > 0) {
                onPick(Double(x) ?? 1, Double(y) ?? 1)
                dismiss()
            }
        }
    }
}
