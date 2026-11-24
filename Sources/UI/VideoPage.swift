import AVFoundation
import Photos
import FossifyCommons
import SwiftUI
import UIKit

/// AVPlayerLayer host.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView { PlayerUIView() }

    func updateUIView(_ v: PlayerUIView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Plays one video: ExoPlayer + VideoFragment's controls (time holder, seek bar, playback speed, mute)
/// and gestures (double tap the sides to seek, vertical swipes for brightness / volume).
@MainActor
@Observable
final class VideoController {
    let id: String
    var player: AVPlayer?
    var isPlaying = false
    var current: Double = 0
    var duration: Double = 0
    var failed = false
    var hasAudio = true
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private let config = Config.shared

    init(id: String) { self.id = id }

    func load(_ medium: Medium, autoplay: Bool) async {
        guard player == nil else {
            if autoplay { play() }
            return
        }
        guard let item = await ImageLoader.playerItem(for: medium.asset) else {
            failed = true
            return
        }
        let p = AVPlayer(playerItem: item)
        p.isMuted = config.muteVideos
        player = p
        duration = medium.asset.duration
        hasAudio = !((try? await item.asset.loadTracks(withMediaType: .audio))?.isEmpty ?? false)
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.current = t.seconds.isFinite ? t.seconds : 0
                self.isPlaying = p.timeControlStatus != .paused
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.config.loopVideos {
                    p.seek(to: .zero)
                    self.play()
                } else {
                    self.isPlaying = false
                    self.config.removeLastVideoPosition(self.id)
                }
            }
        }
        if config.rememberLastVideoPosition {
            let pos = config.lastVideoPosition(id)
            if pos > 0 { await p.seek(to: CMTime(seconds: pos, preferredTimescale: 600)) }
        }
        if autoplay { play() }
    }

    func play() {
        guard let player else { return }
        if duration > 0 && current >= duration - 0.3 { player.seek(to: .zero) }
        player.playImmediately(atRate: config.playbackSpeed)
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
        savePosition()
    }

    func toggle() { isPlaying ? pause() : play() }

    func seek(_ seconds: Double) {
        let t = min(max(seconds, 0), duration)
        current = t
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// FAST_FORWARD_VIDEO_MS = 10 s.
    func skip(forward: Bool) { seek(current + (forward ? 10 : -10)) }

    func setSpeed(_ speed: Float) {
        config.playbackSpeed = speed
        if isPlaying { player?.rate = speed }
    }

    func savePosition() {
        if config.rememberLastVideoPosition && current > 0 && current < duration - 1 {
            config.saveLastVideoPosition(id, current)
        }
    }

    func stop() {
        pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player = nil
    }
}

struct VideoPage: View {
    @Environment(Config.self) private var config
    let medium: Medium
    let isCurrent: Bool
    let showUI: Bool
    /// Horizontal swipes seek (VideoPlayerActivity); otherwise they page.
    var separateScreen = false
    let onTap: (CGPoint, CGSize) -> Void
    @State private var controller: VideoController
    @State private var gestureLabel: String?
    @State private var dragStart: (CGFloat, Double)?
    @State private var appearances = 0

    init(medium: Medium, isCurrent: Bool, showUI: Bool, separateScreen: Bool = false, onTap: @escaping (CGPoint, CGSize) -> Void) {
        self.medium = medium
        self.isCurrent = isCurrent
        self.showUI = showUI
        self.separateScreen = separateScreen
        self.onTap = onTap
        _controller = State(initialValue: VideoController(id: medium.id))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PlayerLayerView(player: controller.player)
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).onEnded { v in
                        controller.skip(forward: v.location.x > geo.size.width / 2)
                        flash(v.location.x > geo.size.width / 2 ? "+10s" : "-10s")
                    })
                    .simultaneousGesture(SpatialTapGesture(count: 1).onEnded { v in onTap(v.location, geo.size) })
                    .simultaneousGesture(config.allowVideoGestures || separateScreen ? sideGestures(geo.size) : nil)
                if controller.failed {
                    Text("Failed to load media.").foregroundStyle(.white)
                } else if !controller.isPlaying || showUI {
                    Button { controller.toggle() } label: {
                        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                            .background(Circle().fill(.black.opacity(0.35)))
                    }
                }
                if let gestureLabel {
                    Text(gestureLabel)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.5)))
                }
                if showUI && !controller.failed {
                    VStack {
                        Spacer()
                        timeHolder
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: "\(isCurrent)-\(appearances)") {
            if isCurrent {
                await controller.load(medium, autoplay: config.autoplayVideos || separateScreen)
            } else {
                controller.pause()
            }
        }
        .onAppear { appearances += 1 }
        .onDisappear { controller.stop() }
    }

    /// bottom_video_time_holder.
    private var timeHolder: some View {
        HStack(spacing: 8) {
            Button { controller.skip(forward: false) } label: { Text(Int(controller.current).formattedDuration()) }
            Slider(value: Binding(get: { controller.current }, set: { controller.seek($0) }), in: 0...max(controller.duration, 0.1))
                .tint(.white)
            Button { controller.skip(forward: true) } label: { Text(Int(controller.duration).formattedDuration()) }
            Menu {
                ForEach([Float(0.25), 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3], id: \.self) { s in
                    Button { controller.setSpeed(s) } label: {
                        if s == config.playbackSpeed { Label(speedText(s), systemImage: "checkmark") } else { Text(speedText(s)) }
                    }
                }
            } label: {
                Text(speedText(config.playbackSpeed)).frame(minWidth: 40)
            }
            Button {
                config.muteVideos.toggle()
                controller.player?.isMuted = config.muteVideos
                if !controller.hasAudio { flash("This video has no audio") }
            } label: {
                Image(systemName: config.muteVideos ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
        }
        .font(.system(size: 14).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
        .padding(.bottom, separateScreen ? 0 : 56)
    }

    private func speedText(_ s: Float) -> String {
        s == s.rounded() ? "\(Int(s))x" : "\(s)x"
    }

    /// MediaSideScroll: left side = brightness, right side = volume; on the separate screen
    /// horizontal swipes seek.
    private func sideGestures(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in
                let dx = v.translation.width, dy = v.translation.height
                if dragStart == nil {
                    if separateScreen && abs(dx) > abs(dy) {
                        dragStart = (-1, controller.current)
                    } else if abs(dy) > abs(dx) {
                        let left = v.startLocation.x < size.width / 2
                        dragStart = (left ? 0 : 1, left ? Double(UIScreen.main.brightness) : Double(controller.player?.volume ?? 1))
                    } else {
                        return
                    }
                }
                guard let (kind, start) = dragStart else { return }
                if kind < 0 {
                    let t = start + Double(dx / size.width) * max(controller.duration, 1) / 2
                    controller.seek(t)
                    flash(Int(min(max(t, 0), controller.duration)).formattedDuration(), sticky: true)
                } else {
                    let value = min(max(start - Double(dy / (size.height * 0.8)), 0), 1)
                    if kind == 0 {
                        UIScreen.main.brightness = value
                        flash("Brightness \(Int(value * 100))%", sticky: true)
                    } else {
                        controller.player?.volume = Float(value)
                        flash("Volume \(Int(value * 100))%", sticky: true)
                    }
                }
            }
            .onEnded { _ in
                dragStart = nil
                flash(gestureLabel ?? "")
            }
    }

    private func flash(_ text: String, sticky: Bool = false) {
        gestureLabel = text.isEmpty ? nil : text
        guard !sticky else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if gestureLabel == text { gestureLabel = nil }
        }
    }
}

/// VideoPlayerActivity: "Play videos on a separate screen with horizontal gestures".
struct SeparateVideoPlayer: View {
    @Environment(MediaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    let id: String
    @State private var medium: Medium?
    @State private var showUI = true
    @State private var share: ShareItems?
    @State private var properties = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let medium {
                VideoPage(medium: medium, isCurrent: true, showUI: showUI, separateScreen: true) { _, _ in
                    withAnimation { showUI.toggle() }
                }
                .ignoresSafeArea()
                if showUI {
                    HStack(spacing: 0) {
                        IconButton(icon: "arrow.left") { router.pop() }
                        Text(medium.name).font(.system(size: 18, weight: .medium)).lineLimit(1)
                        Spacer()
                        IconButton(icon: "square.and.arrow.up") { shareMedium(medium) }
                        OverflowMenu {
                            Button { properties = true } label: { Label("Properties", systemImage: "info.circle") }
                            Menu {
                                OrientationMenuItems()
                            } label: { Label("Change orientation", systemImage: "rotate.right") }
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
                }
            }
        }
        .statusBarHidden(!showUI)
        .task {
            let o = PHFetchOptionsFactory.all()
            if let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: o).firstObject {
                medium = Medium(asset: a, info: store.fileInfo[id] ?? MediaStore.readInfo(a), folderName: "")
            }
        }
        .sheet(item: $share) { ShareSheet(items: $0.urls) }
        .sheet(isPresented: $properties) { if let medium { PropertiesView(media: [medium]) } }
        .onDisappear { OrientationControl.reset() }
    }

    private func shareMedium(_ m: Medium) {
        Task { @MainActor in
            if let url = await ImageLoader.exportedFile(for: m) { share = ShareItems([url]) }
        }
    }
}


enum PHFetchOptionsFactory {
    /// Including hidden assets, for fetching by identifier.
    static func all() -> PHFetchOptions {
        let o = PHFetchOptions()
        o.includeHiddenAssets = true
        return o
    }
}
