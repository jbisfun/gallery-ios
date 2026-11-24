import FossifyCommons
import Photos
import UIKit

/// Publishes the folders (with downscaled cover thumbnails written as files) for the iOS
/// home-screen folder widget (fossify-ios/widgets-ios), which can't run MediaStore itself.
public enum GalleryWidgetData {
    static let snapshotName = "gallery"
    @MainActor private static var generation = 0

    /// Call once at launch (LauncherApp.init): publishes now (when the library is already
    /// accessible) and whenever the folders or their covers change.
    @MainActor
    public static func install() {
        MediaStore.widgets.startForWidgets()
        WidgetBridge.track { publish() }
    }

    /// `fossify://open/gallery?folder=<path>`: the app opens on its folder list.
    @MainActor
    public static func handle(_ url: URL) {}

    @MainActor
    static func publish() {
        let albums = MediaStore.widgets.allAlbums
        let crop = Config.shared.cropThumbnails
        guard MediaStore.widgets.loadedInitial else { return }
        generation += 1
        let token = generation
        let items = albums.map { ($0.path, $0.name, $0.mediaCount, $0.thumbnail) }
        Task.detached(priority: .utility) {
            var folders: [GalleryWidgetSnapshot.Folder] = []
            var keep = Set<String>()
            for (path, name, count, asset) in items {
                var file: String?
                if let asset {
                    let stamp = Int(asset.modificationDate?.timeIntervalSince1970 ?? 0)
                    let id = asset.localIdentifier.map { $0.isLetter || $0.isNumber ? $0 : "_" }
                    let rel = "gallery/\(String(id))-\(stamp).jpg"
                    if let url = WidgetBridge.fileURL(rel) {
                        if !FileManager.default.fileExists(atPath: url.path),
                           let image = await ImageLoader.image(for: asset, size: CGSize(width: 360, height: 360), contentMode: .aspectFill),
                           let data = image.jpegData(compressionQuality: 0.8) {
                            try? data.write(to: url, options: .atomic)
                        }
                        if FileManager.default.fileExists(atPath: url.path) {
                            file = rel
                            keep.insert(url.lastPathComponent)
                        }
                    }
                }
                folders.append(.init(path: path, name: name, thumbnail: file, count: count))
            }
            let snapshot = GalleryWidgetSnapshot(folders: folders, cropThumbnails: crop)
            await MainActor.run {
                guard token == generation else { return }
                WidgetBridge.save(snapshot, snapshotName, reload: [WidgetKinds.galleryFolder])
                // Drop covers no folder uses any more.
                if let dir = WidgetBridge.fileURL("gallery/x")?.deletingLastPathComponent(),
                   let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                    for f in files where !keep.contains(f) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
                }
            }
        }
    }
}
