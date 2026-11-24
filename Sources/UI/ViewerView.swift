import FossifyCommons
import Photos
import SwiftUI
import UIKit

/// requestedOrientation helpers (screen rotation setting + "Change orientation" menu).
@MainActor
enum OrientationControl {
    static func set(_ mask: UIInterfaceOrientationMask) { OrientationLock.set(mask: mask) }
    static func reset() { OrientationLock.set(mask: .all) }
}

struct OrientationMenuItems: View {
    var body: some View {
        Button("Force portrait") { OrientationControl.set(.portrait) }
        Button("Force landscape") { OrientationControl.set(.landscapeRight) }
        Button("Force landscape (reverse)") { OrientationControl.set(.landscapeLeft) }
        Button("Use default orientation") { OrientationControl.reset() }
    }
}

/// ViewPagerActivity: swipe through the media of a folder in fullscreen.
struct ViewerView: View {
    @Environment(MediaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let path: String
    let startID: String
    let only: [String]?
    var startSlideshow = false

    @State private var media: [Medium] = []
    @State private var currentID: String?
    @State private var showUI = true
    @State private var zoomed = false
    @State private var rotations: [String: Int] = [:]
    @State private var dragY: CGFloat = 0
    @State private var fadeOpacity: Double = 1
    @State private var check: SecurityCheck?
    @State private var originalBrightness: CGFloat?

    @State private var slideshowIDs: [String] = []
    @State private var slideshowTask: Task<Void, Never>?
    @State private var showSlideshowDialog = false

    @State private var properties = false
    @State private var share: ShareItems?
    @State private var copyMove: Bool?
    @State private var resize = false
    @State private var confirmDelete = false

    private var current: Medium? { media.first { $0.id == currentID } }
    private var visibleActions: Int { config.bottomActions ? config.visibleBottomActions : 0 }

    var body: some View {
        ZStack {
            (config.blackBackground ? Color.black : palette.backgroundColor).ignoresSafeArea()
            pager
                .offset(y: dragY)
                .opacity(fadeOpacity * (1 - Double(min(abs(dragY) / 600, 0.6))))
                .ignoresSafeArea()
            if let current {
                overlays(current)
            }
        }
        .statusBarHidden(!showUI)
        .persistentSystemOverlays(showUI ? .automatic : .hidden)
        .task(id: store.version) { await load() }
        .onAppear(perform: enter)
        .onDisappear(perform: leave)
        .onChange(of: currentID) { _, _ in applyAspectRatioRotation() }
        .securityCheck($check)
        .sheet(isPresented: $properties) { if let current { PropertiesView(media: [current]) } }
        .sheet(item: $share) { ShareSheet(items: $0.urls) }
        .sheet(item: Binding(get: { copyMove.map { IdentifiedString(value: $0 ? "move" : "copy") } }, set: { copyMove = $0.map { $0.value == "move" } })) { item in
            let move = item.value == "move"
            PickDirectoryDialog(title: move ? "Move to" : "Copy to", exclude: path) { target in
                guard let id = currentID else { return }
                let run = { store.copyMove([id], to: target, from: path.isEmpty ? nil : path, move: move) }
                if move, let c = SecurityCheck.deleteProtection(run) { check = c } else { run() }
            }
        }
        .sheet(isPresented: $resize) {
            if let current {
                ResizeDialog(size: CGSize(width: current.width, height: current.height)) { size in
                    store.resize([current.id], size: size, album: path.isEmpty ? nil : path)
                }
            }
        }
        .sheet(isPresented: $showSlideshowDialog) { SlideshowDialog { startSlideshowNow() } }
        .alert("Are you sure you want to delete 1 item?", isPresented: $confirmDelete) {
            Button("No", role: .cancel) {}
            Button("Yes") { deleteCurrent() }
        }
    }

    // MARK: Pager

    private var pager: some View {
        TabView(selection: $currentID) {
            ForEach(media) { m in
                page(m).tag(Optional(m.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .simultaneousGesture(downGesture)
        .overlay(alignment: .leading) {
            if config.allowPhotoGestures && current?.isVideo == false && !zoomed {
                BrightnessStrip()
            }
        }
    }

    @ViewBuilder
    private func page(_ m: Medium) -> some View {
        if m.isVideo {
            VideoPage(medium: m, isCurrent: m.id == currentID, showUI: showUI) { p, s in tapped(p, s) }
        } else {
            PhotoPage(medium: m, rotation: Binding(get: { rotations[m.id] ?? 0 }, set: { rotations[m.id] = $0 }),
                      onTap: { p, s in tapped(p, s) }, onZoomChange: { z in if m.id == currentID { zoomed = z } })
        }
    }

    /// allowDownGesture: drag down to close.
    private var downGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { v in
                guard config.allowDownGesture, !zoomed, v.translation.height > 0,
                      abs(v.translation.height) > abs(v.translation.width) * 1.5 else { return }
                dragY = v.translation.height
            }
            .onEnded { v in
                if dragY > 150 { router.pop() }
                withAnimation(.spring(duration: 0.25)) { dragY = 0 }
            }
    }

    // MARK: Overlays

    @ViewBuilder
    private func overlays(_ m: Medium) -> some View {
        VStack(spacing: 0) {
            if showUI { topBar(m) }
            Spacer()
            if config.showExtendedDetails && (showUI || !config.hideExtendedDetails) {
                ExtendedDetails(medium: m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            if showUI && visibleActions != 0 { bottomBar(m) }
        }
        .foregroundStyle(.white)
    }

    private func topBar(_ m: Medium) -> some View {
        let rotated = (rotations[m.id] ?? 0) != 0
        return HStack(spacing: 0) {
            IconButton(icon: "arrow.left") { router.pop() }
            Text(m.name).font(.system(size: 18, weight: .medium)).lineLimit(1)
            Spacer()
            if rotated {
                IconButton(icon: "checkmark") { saveRotation(m) }
            }
            if visibleActions & BottomAction.delete.rawValue == 0 { IconButton(icon: "trash") { askDelete() } }
            if visibleActions & BottomAction.share.rawValue == 0 { IconButton(icon: "square.and.arrow.up") { shareMedium(m) } }
            OverflowMenu { topMenu(m) }
        }
        .padding(.horizontal, 4)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))
    }

    /// menu_viewpager.xml (items not shown as bottom actions).
    @ViewBuilder
    private func topMenu(_ m: Medium) -> some View {
        let a = visibleActions
        if m.isImage && a & BottomAction.rotate.rawValue == 0 {
            Menu {
                Button("Rotate right") { rotate(m, 90) }
                Button("Rotate left") { rotate(m, 270) }
                Button("Rotate by 180º") { rotate(m, 180) }
            } label: { Label("Rotate", systemImage: "rotate.right") }
        }
        if a & BottomAction.properties.rawValue == 0 {
            Button { properties = true } label: { Label("Properties", systemImage: "info.circle") }
        }
        if a & BottomAction.edit.rawValue == 0 && !m.isVideo {
            Button { router.push(.editor(m.id)) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
        }
        if a & BottomAction.toggleFavorite.rawValue == 0 {
            Button { store.setFavorite([m.id], !m.isFavorite) } label: {
                Label(m.isFavorite ? "Remove from favorites" : "Add to favorites", systemImage: m.isFavorite ? "star.slash" : "star")
            }
        }
        if a & BottomAction.toggleVisibility.rawValue == 0 {
            Button { store.setHidden([m.id], !m.isHidden) } label: { Label(m.isHidden ? "Unhide" : "Hide", systemImage: m.isHidden ? "eye" : "eye.slash") }
        }
        if !m.isVideo {
            Button { copyToClipboard(m) } label: { Label("Copy to clipboard", systemImage: "doc.on.clipboard") }
        }
        if a & BottomAction.copy.rawValue == 0 {
            Button { copyMove = false } label: { Label("Copy to", systemImage: "doc.on.doc") }
        }
        if a & BottomAction.move.rawValue == 0 {
            Button { copyMove = true } label: { Label("Move to", systemImage: "folder") }
        }
        Button { openWith(m) } label: { Label("Open with", systemImage: "arrow.up.forward.app") }
        if a & BottomAction.changeOrientation.rawValue == 0 && (rotations[m.id] ?? 0) == 0 {
            Menu { OrientationMenuItems() } label: { Label("Change orientation", systemImage: "rectangle.portrait.rotate") }
        }
        if !m.isVideo {
            Button { printMedium(m) } label: { Label("Print", systemImage: "printer") }
        }
        if m.isImage && a & BottomAction.resize.rawValue == 0 {
            Button { resize = true } label: { Label("Resize", systemImage: "arrow.up.left.and.arrow.down.right") }
        }
        if a & BottomAction.showOnMap.rawValue == 0 {
            Button { showOnMap(m, store: store) } label: { Label("Show on map", systemImage: "map") }
        }
        if a & BottomAction.slideshow.rawValue == 0 {
            Button { showSlideshowDialog = true } label: { Label("Slideshow", systemImage: "play.rectangle") }
        }
        Button { router.push(.settings) } label: { Label("Settings", systemImage: "gearshape") }
    }

    /// bottom_actions.xml.
    private func bottomBar(_ m: Medium) -> some View {
        let a = visibleActions
        return HStack(spacing: 0) {
            ForEach(BottomAction.available.filter { a & $0.rawValue != 0 }, id: \.rawValue) { action in
                if let icon = icon(action, m) {
                    Button { perform(action, m) } label: {
                        Image(systemName: icon).font(.system(size: 20)).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .contextMenu { Text(action.title) }
                }
            }
        }
        .padding(.bottom, 4)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
    }

    private func icon(_ a: BottomAction, _ m: Medium) -> String? {
        switch a {
        case .toggleFavorite: return m.isFavorite ? "star.fill" : "star"
        case .edit: return m.isVideo ? nil : "slider.horizontal.3"
        case .share: return "square.and.arrow.up"
        case .delete: return "trash"
        case .rotate: return m.isImage ? "rotate.right" : nil
        case .properties: return "info.circle"
        case .changeOrientation: return "rectangle.portrait.rotate"
        case .slideshow: return "play.rectangle"
        case .showOnMap: return "map"
        case .toggleVisibility: return m.isHidden ? "eye" : "eye.slash"
        case .copy: return "doc.on.doc"
        case .move: return "folder"
        case .resize: return m.isImage ? "arrow.up.left.and.arrow.down.right" : nil
        case .rename, .setAs: return nil
        }
    }

    private func perform(_ a: BottomAction, _ m: Medium) {
        switch a {
        case .toggleFavorite: store.setFavorite([m.id], !m.isFavorite)
        case .edit: router.push(.editor(m.id))
        case .share: shareMedium(m)
        case .delete: askDelete()
        case .rotate: rotate(m, 90)
        case .properties: properties = true
        case .changeOrientation: cycleOrientation()
        case .slideshow: showSlideshowDialog = true
        case .showOnMap: showOnMap(m, store: store)
        case .toggleVisibility: store.setHidden([m.id], !m.isHidden)
        case .copy: copyMove = false
        case .move: copyMove = true
        case .resize: resize = true
        case .rename, .setAs: break
        }
    }

    // MARK: Loading / lifecycle

    private func load() async {
        var list = await store.media(in: path)
        if let only {
            let set = Set(only)
            list = list.filter { set.contains($0.id) }
        }
        let previous = media
        media = list
        if currentID == nil {
            currentID = list.contains { $0.id == startID } ? startID : list.first?.id
            if startSlideshow { startSlideshowNow() }
        } else if let id = currentID, !list.contains(where: { $0.id == id }) {
            // The current medium went away (deleted, moved, hidden): show its neighbour.
            let oldIndex = previous.firstIndex { $0.id == id } ?? 0
            let ids = Set(list.map(\.id))
            let next = previous[oldIndex...].first { ids.contains($0.id) } ?? previous[..<oldIndex].last { ids.contains($0.id) }
            currentID = next?.id
        }
        if list.isEmpty { router.pop() }
    }

    private func enter() {
        showUI = !config.hideSystemUI
        if config.maxBrightness {
            originalBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1
        }
        UIApplication.shared.isIdleTimerDisabled = config.keepScreenOn
        applyAspectRatioRotation()
    }

    private func leave() {
        slideshowTask?.cancel()
        if let originalBrightness { UIScreen.main.brightness = originalBrightness }
        UIApplication.shared.isIdleTimerDisabled = false
        OrientationControl.reset()
    }

    /// Screen rotation "Aspect ratio": landscape media rotate the screen to landscape.
    private func applyAspectRatioRotation() {
        guard config.screenRotation == .aspectRatio, let m = current else { return }
        OrientationControl.set(m.width > m.height ? .landscapeRight : .portrait)
    }

    private func cycleOrientation() {
        switch OrientationLock.mask {
        case .portrait: OrientationControl.set(.landscapeRight)
        case .landscapeRight: OrientationControl.set(.landscapeLeft)
        case .landscapeLeft: OrientationControl.reset()
        default: OrientationControl.set(.portrait)
        }
    }

    // MARK: Taps

    private func tapped(_ point: CGPoint, _ size: CGSize) {
        if !slideshowIDs.isEmpty {
            stopSlideshow()
            return
        }
        if config.allowInstantChange && !zoomed {
            if point.x < size.width * 0.15 { go(-1); return }
            if point.x > size.width * 0.85 { go(1); return }
        }
        withAnimation(.easeInOut(duration: 0.2)) { showUI.toggle() }
    }

    private func go(_ delta: Int) {
        guard let i = media.firstIndex(where: { $0.id == currentID }) else { return }
        let j = i + delta
        guard media.indices.contains(j) else { return }
        withAnimation { currentID = media[j].id }
    }

    // MARK: Actions

    private func askDelete() {
        if config.skipDeleteConfirmation || config.tempSkipDeleteConfirmation { deleteCurrent() } else { confirmDelete = true }
    }

    private func deleteCurrent() {
        guard let id = currentID else { return }
        let run = { store.delete([id]) }
        if let c = SecurityCheck.deleteProtection(run) { check = c } else { run() }
    }

    private func shareMedium(_ m: Medium) {
        Task { @MainActor in
            if let url = await ImageLoader.exportedFile(for: m) { share = ShareItems([url]) }
        }
    }

    private func openWith(_ m: Medium) {
        Task { @MainActor in
            if let url = await ImageLoader.exportedFile(for: m), !Launcher.openWith(url) { store.toast = "No valid app found" }
        }
    }

    private func copyToClipboard(_ m: Medium) {
        Task { @MainActor in
            if let image = await ImageLoader.image(for: m.asset, size: PHImageManagerMaximumSize) {
                UIPasteboard.general.image = image
                store.toast = "Copied to clipboard"
            }
        }
    }

    private func printMedium(_ m: Medium) {
        Task { @MainActor in
            guard let data = await ImageLoader.data(for: m.asset) else { return }
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .photo
            info.jobName = m.name
            let controller = UIPrintInteractionController.shared
            controller.printInfo = info
            controller.printingItem = data
            controller.present(animated: true)
        }
    }

    /// Rotating shows the rotated image; the check mark saves it (menu_save_as).
    private func rotate(_ m: Medium, _ degrees: Int) {
        rotations[m.id] = ((rotations[m.id] ?? 0) + degrees) % 360
    }

    private func saveRotation(_ m: Medium) {
        guard let degrees = rotations[m.id], degrees != 0 else { return }
        store.rotate([m.id], degrees: degrees)
        rotations[m.id] = 0
    }

    // MARK: Slideshow

    private func startSlideshowNow() {
        var list = media.filter { m in
            (!m.isVideo || config.slideshowIncludeVideos) && (!m.isGif || config.slideshowIncludeGIFs)
        }
        if config.slideshowRandomOrder {
            list.shuffle()
            if let cur = list.firstIndex(where: { $0.id == currentID }) { list.swapAt(0, cur) }
        } else if let start = list.firstIndex(where: { $0.id == currentID }) {
            if config.slideshowMoveBackwards {
                list = Array(list[...start].reversed()) + (config.loopSlideshow ? Array(list[(start + 1)...].reversed()) : [])
            } else {
                list = Array(list[start...]) + (config.loopSlideshow ? Array(list[..<start]) : [])
            }
        }
        guard !list.isEmpty else {
            store.toast = "No media for the slideshow have been found"
            return
        }
        slideshowIDs = list.map(\.id)
        withAnimation { showUI = false }
        UIApplication.shared.isIdleTimerDisabled = true
        if currentID != slideshowIDs.first { currentID = slideshowIDs.first }
        slideshowTask?.cancel()
        slideshowTask = Task { @MainActor in
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(config.slideshowInterval, 1)))
                if Task.isCancelled { return }
                i += 1
                if i >= slideshowIDs.count {
                    if config.loopSlideshow {
                        i = 0
                    } else {
                        store.toast = "The slideshow ended"
                        stopSlideshow()
                        return
                    }
                }
                showSlide(slideshowIDs[i])
            }
        }
    }

    private func showSlide(_ id: String) {
        switch config.slideshowAnimation {
        case .none:
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { currentID = id }
        case .slide:
            withAnimation(.easeInOut(duration: 0.5)) { currentID = id }
        case .fade:
            Task { @MainActor in
                withAnimation(.easeIn(duration: 0.75)) { fadeOpacity = 0 }
                try? await Task.sleep(for: .milliseconds(750))
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { currentID = id }
                withAnimation(.easeOut(duration: 0.75)) { fadeOpacity = 1 }
            }
        }
    }

    private func stopSlideshow() {
        slideshowTask?.cancel()
        slideshowTask = nil
        slideshowIDs = []
        fadeOpacity = 1
        UIApplication.shared.isIdleTimerDisabled = config.keepScreenOn
        withAnimation { showUI = true }
    }
}

/// allowPhotoGestures: vertical swipes along the left edge change the screen brightness.
struct BrightnessStrip: View {
    @State private var start: CGFloat?
    @State private var label: String?

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .frame(width: 44)
                .gesture(DragGesture(minimumDistance: 10)
                    .onChanged { v in
                        if start == nil { start = UIScreen.main.brightness }
                        let value = min(max((start ?? 0.5) - v.translation.height / (geo.size.height * 0.8), 0), 1)
                        UIScreen.main.brightness = value
                        label = "Brightness \(Int(value * 100))%"
                    }
                    .onEnded { _ in
                        start = nil
                        label = nil
                    })
                .overlay {
                    if let label {
                        Text(label).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                            .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.5)))
                            .fixedSize()
                            .offset(x: geo.size.width / 2 - 22)
                    }
                }
        }
        .frame(width: 44)
    }
}

/// Extended details shown over fullscreen media (ViewPagerFragment.getMediumExtendedDetails).
struct ExtendedDetails: View {
    @Environment(Config.self) private var config
    let medium: Medium
    @State private var text = ""

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 2)
            .task(id: "\(medium.id)-\(config.extendedDetails)") { text = await build() }
    }

    private func build() async -> String {
        let flags = config.extendedDetails
        let fmt = DateTimeFormat.shared
        var lines: [String] = []
        if flags & ExtendedDetail.name.rawValue != 0 { lines.append(medium.name) }
        if flags & ExtendedDetail.path.rawValue != 0 && !medium.folderName.isEmpty { lines.append("\(medium.folderName)/") }
        if flags & ExtendedDetail.size.rawValue != 0 && medium.size > 0 { lines.append(medium.size.formattedSize) }
        if flags & ExtendedDetail.resolution.rawValue != 0 { lines.append("\(medium.width) x \(medium.height)") }
        if flags & ExtendedDetail.lastModified.rawValue != 0 { lines.append(fmt.format(medium.modified)) }
        var props: [CFString: Any] = [:]
        if !medium.isVideo && flags & (ExtendedDetail.dateTaken.rawValue | ExtendedDetail.cameraModel.rawValue | ExtendedDetail.exifProperties.rawValue) != 0,
           let data = await ImageLoader.data(for: medium.asset) {
            props = Exif.properties(data)
            if flags & ExtendedDetail.dateTaken.rawValue != 0, let d = Exif.dateTaken(data) { lines.append(fmt.format(d)) }
        }
        if flags & ExtendedDetail.cameraModel.rawValue != 0 {
            let c = Exif.cameraModel(props)
            if !c.isEmpty { lines.append(c) }
        }
        if flags & ExtendedDetail.exifProperties.rawValue != 0 {
            let e = Exif.exifProperties(props)
            if !e.isEmpty { lines.append(e) }
        }
        if flags & ExtendedDetail.gps.rawValue != 0, let loc = medium.location {
            lines.append(String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
        }
        return lines.joined(separator: "\n")
    }
}
