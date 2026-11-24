import FossifyCommons
import Photos
import SwiftUI
import UIKit

/// Thumbnail of an asset through the shared PHCachingImageManager (Glide's loadImage()).
struct Thumbnail: View {
    @Environment(MediaStore.self) private var store
    let asset: PHAsset?
    var crop = true
    var animateGif = false
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: crop ? .fill : .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if failed {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: "\(asset?.localIdentifier ?? "")-\(asset?.modificationDate?.timeIntervalSince1970 ?? 0)-\(Int(geo.size.width))-\(animateGif)") {
                await load(geo.size)
            }
        }
    }

    private func load(_ size: CGSize) async {
        guard let asset, size.width > 0 else { image = nil; return }
        if animateGif, asset.playbackStyle == .imageAnimated, let data = await ImageLoader.data(for: asset) {
            image = ImageLoader.animatedImage(data)
            return
        }
        let scale = UIScreen.main.scale
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = true
        o.deliveryMode = .opportunistic
        o.resizeMode = .fast
        for await (img, degraded) in imageStream(asset, target, o) {
            if Task.isCancelled { return }
            if let img { image = img; failed = false } else if !degraded && image == nil { failed = true }
        }
    }

    private func imageStream(_ asset: PHAsset, _ target: CGSize, _ o: PHImageRequestOptions) -> AsyncStream<(UIImage?, Bool)> {
        let manager = store.imageManager
        return AsyncStream { cont in
            let id = manager.requestImage(for: asset, targetSize: target, contentMode: crop ? .aspectFill : .aspectFit, options: o) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                cont.yield((img, degraded))
                if !degraded { cont.finish() }
            }
            cont.onTermination = { _ in manager.cancelImageRequest(id) }
        }
    }
}

/// photo_item_grid / video_item_grid / photo_item_list.
struct MediumCell: View {
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let medium: Medium
    let list: Bool
    let selected: Bool
    var selecting = false

    var body: some View {
        if list { listCell } else { gridCell }
    }

    private var gridCell: some View {
        Thumbnail(asset: medium.asset, crop: config.cropThumbnails, animateGif: config.animateGifs)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: config.fileRoundedCorners ? 12 : 0))
            .overlay(alignment: .topLeading) {
                if medium.isVideo {
                    HStack(spacing: 2) {
                        Image(systemName: "play.fill").font(.system(size: 13))
                        if config.showThumbnailVideoDuration {
                            Text(medium.duration.formattedDuration()).font(.system(size: 13))
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .padding(6)
                } else if config.showThumbnailFileTypes, let label = typeLabel {
                    Text(label).font(.system(size: 15, weight: .bold)).foregroundStyle(.white).shadow(color: .black, radius: 2).padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 4) {
                        if config.markFavoriteItems && medium.isFavorite {
                            Image(systemName: "star.fill").font(.system(size: 13)).foregroundStyle(.white).shadow(color: .black, radius: 2)
                        }
                        if config.displayFileNames {
                            Text(medium.name).font(.system(size: 12)).foregroundStyle(.white).lineLimit(2).shadow(color: .black, radius: 2)
                        }
                        if medium.isHidden {
                            Image(systemName: "eye.slash").font(.system(size: 12)).foregroundStyle(.white).shadow(color: .black, radius: 2)
                        }
                    }
                    .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) { check.padding(8) }
            .contentShape(Rectangle())
    }

    private var listCell: some View {
        HStack(spacing: 12) {
            Thumbnail(asset: medium.asset, crop: true, animateGif: config.animateGifs)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottomTrailing) {
                    if config.markFavoriteItems && medium.isFavorite {
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.white).shadow(color: .black, radius: 2).padding(4)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(medium.name).font(.system(size: 16)).lineLimit(2)
                if medium.isVideo {
                    Text(medium.duration.formattedDuration()).font(.system(size: 14)).foregroundStyle(palette.secondaryText)
                } else if config.showThumbnailFileTypes, let label = typeLabel {
                    Text(label).font(.system(size: 14)).foregroundStyle(palette.secondaryText)
                }
            }
            Spacer()
            check
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(selected ? palette.primaryColor.opacity(0.25) : .clear)
        .contentShape(Rectangle())
    }

    private var typeLabel: String? {
        if medium.isGif { return "GIF" }
        if medium.isRaw { return "RAW" }
        return nil
    }

    @ViewBuilder private var check: some View {
        if selected {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.onPrimary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(palette.primaryColor))
        }
    }
}

/// directory_item_grid_square / directory_item_grid_rounded_corners / directory_item_list.
struct DirectoryCell: View {
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let dir: Directory
    let list: Bool
    let selected: Bool
    let locked: Bool
    var dragging = false

    private var title: String {
        var name = dir.name
        if config.showFolderMediaCount == .brackets { name += " (\(dir.mediaCount))" }
        return name
    }

    var body: some View {
        if list { listCell } else if config.folderStyle == .square { squareCell } else { roundedCell }
    }

    @ViewBuilder private var thumb: some View {
        if locked {
            ZStack {
                palette.backgroundColor
                Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(palette.textColor)
            }
        } else {
            Thumbnail(asset: dir.thumbnail, crop: config.cropThumbnails, animateGif: config.animateGifs)
        }
    }

    private var squareCell: some View {
        thumb
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15)).lineLimit(config.limitFolderTitle ? 1 : 3).truncationMode(.middle)
                    if config.showFolderMediaCount == .line { Text("\(dir.mediaCount)").font(.system(size: 14)) }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .topLeading) { pin.padding(6) }
            .overlay(alignment: .topTrailing) { check.padding(8) }
            .overlay(alignment: .top) { dragHandle }
            .contentShape(Rectangle())
    }

    private var roundedCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            thumb
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topLeading) { pin.padding(6) }
                .overlay(alignment: .topTrailing) { check.padding(8) }
                .overlay(alignment: .top) { dragHandle }
            Text(title).font(.system(size: 15)).lineLimit(config.limitFolderTitle ? 1 : 3).truncationMode(.middle).padding(.horizontal, 4)
            if config.showFolderMediaCount == .line {
                Text("\(dir.mediaCount)").font(.system(size: 14)).foregroundStyle(palette.secondaryText).padding(.horizontal, 4)
            }
        }
        .padding(.bottom, 6)
        .contentShape(Rectangle())
    }

    private var listCell: some View {
        HStack(spacing: 12) {
            thumb.frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16)).lineLimit(config.limitFolderTitle ? 1 : 2).truncationMode(.middle)
                Text(dir.isUserAlbum ? "Albums/" : "Library/").font(.system(size: 14)).foregroundStyle(palette.secondaryText)
                HStack(spacing: 12) {
                    if config.showFolderMediaCount == .line { Text("\(dir.mediaCount)") }
                    if dir.size > 0 { Text(dir.size.formattedSize) }
                }
                .font(.system(size: 14)).foregroundStyle(palette.secondaryText)
            }
            Spacer()
            pin
            if dragging { Image(systemName: "line.3.horizontal").foregroundStyle(palette.textColor) }
            check
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(selected ? palette.primaryColor.opacity(0.25) : .clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var pin: some View {
        if config.pinnedFolders.contains(dir.path) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.black.opacity(0.6)))
        }
    }

    @ViewBuilder private var dragHandle: some View {
        if dragging {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.black.opacity(0.6)))
                .padding(8)
        }
    }

    @ViewBuilder private var check: some View {
        if selected {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.onPrimary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(palette.primaryColor))
        }
    }
}

/// Two-line placeholder shown when there's nothing to show.
struct Placeholder: View {
    @Environment(\.palette) private var palette
    let text: String
    var action: String?
    var onAction: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Text(text)
                .font(.system(size: 17).italic())
                .foregroundStyle(palette.textColor)
                .multilineTextAlignment(.center)
            if let action {
                Button(action: onAction) {
                    Text(action).font(.system(size: 17)).underline().foregroundStyle(palette.primaryColor)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// MySearchMenu: rounded search field with action icons and an overflow menu.
struct SearchMenuBar<Actions: View, MenuItems: View>: View {
    @Environment(\.palette) private var palette
    let hint: String
    @Binding var query: String
    @Binding var searching: Bool
    /// When set, tapping the field opens this instead of searching inline (SearchActivity).
    var onTapSearch: (() -> Void)?
    /// Only the main screen shows the launcher's home button.
    var showClose = true
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var menu: () -> MenuItems
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            if !searching && showClose { CloseAppButton() }
            Button {
                if searching {
                    query = ""
                    searching = false
                    focused = false
                } else if let onTapSearch {
                    onTapSearch()
                } else {
                    searching = true
                    focused = true
                }
            } label: {
                Image(systemName: searching ? "arrow.left" : "magnifyingglass").font(.system(size: 18)).frame(width: 48, height: 48)
            }
            ZStack {
                TextField("", text: $query, prompt: Text(hint).foregroundStyle(palette.secondaryText))
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onChange(of: focused) { _, f in if f { searching = true } }
                    .disabled(onTapSearch != nil)
                if let onTapSearch {
                    Color.clear.contentShape(Rectangle()).onTapGesture(perform: onTapSearch)
                }
            }
            if !query.isEmpty {
                IconButton(icon: "xmark") { query = "" }
            }
            if !searching { actions() }
            OverflowMenu(content: menu)
        }
        .foregroundStyle(palette.textColor)
        .background(Capsule().fill(palette.surface))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Action mode bar (cab_*.xml): commons' ActionModeBar with the icons and an overflow menu.
struct SelectionBar<Actions: View, MenuItems: View>: View {
    let count: Int
    let onClose: () -> Void
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var menu: () -> MenuItems

    var body: some View {
        ActionModeBar(count: count, onClose: onClose) {
            actions()
            OverflowMenu(content: menu)
        }
    }
}

/// MyRecyclerView's zoom listener: pinching changes the column count.
struct PinchColumns: ViewModifier {
    let count: Int
    let set: (Int) -> Void
    @State private var startCount: Int?

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            MagnifyGesture()
                .onChanged { v in
                    let base = startCount ?? count
                    if startCount == nil { startCount = count }
                    let target = v.magnification > 1.25 ? base - 1 : (v.magnification < 0.8 ? base + 1 : base)
                    let clamped = min(max(target, 1), maxColumnCount)
                    if clamped != count { set(clamped) }
                }
                .onEnded { _ in startCount = nil }
        )
    }
}

extension View {
    func pinchColumns(_ count: Int, set: @escaping (Int) -> Void) -> some View { modifier(PinchColumns(count: count, set: set)) }

    /// Like Fossify's alert dialogs: a confirmation with Yes/No.
    func confirm(_ message: String?, isPresented: Binding<Bool>, yes: String = "Yes", destructive: Bool = false, action: @escaping () -> Void) -> some View {
        alert(message ?? "", isPresented: isPresented) {
            Button("No", role: .cancel) {}
            Button(yes, role: destructive ? .destructive : nil, action: action)
        }
    }
}

/// Wraps an optional string for `.sheet(item:)` / `.alert` style bindings.
struct IdentifiedString: Identifiable, Hashable {
    let value: String
    var id: String { value }
}

/// Opens Apple Maps at the coordinates (showOnMap()).
@MainActor
func showOnMap(_ m: Medium, store: MediaStore) {
    guard let loc = m.location else {
        store.toast = "Unknown location"
        return
    }
    let c = loc.coordinate
    Launcher.open(URL(string: "https://maps.apple.com/?ll=\(c.latitude),\(c.longitude)&q=\(c.latitude),\(c.longitude)"))
}

/// The current window scene's interface orientation.
@MainActor
var isLandscape: Bool {
    (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation.isLandscape ?? false
}
