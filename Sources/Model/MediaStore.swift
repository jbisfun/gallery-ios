import FossifyCommons
import Foundation
import ImageIO
import Observation
import Photos
import UIKit
import UniformTypeIdentifiers

/// MediaFetcher + the file operations of Activity.kt/Context.kt, on top of PhotoKit:
/// folders are albums, files are assets, and every change goes through PHPhotoLibrary.
@MainActor
@Observable
final class MediaStore: NSObject, PHPhotoLibraryChangeObserver {
    enum Access { case unknown, granted, limited, denied }

    var access: Access = .unknown
    var directories: [Directory] = []
    /// Every album, including excluded and empty ones (copy/move targets, managing excluded folders).
    var allAlbums: [Directory] = []
    var loadedInitial = false
    var toast: String?
    /// Bumped on every library change; media screens reload when it changes.
    var version = 0

    @ObservationIgnored let imageManager = PHCachingImageManager()
    @ObservationIgnored private(set) var fileInfo: [String: FileInfo] = [:]
    @ObservationIgnored private var fillingInfo = false
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var observing = false

    private let config = Config.shared

    override init() {
        super.init()
        fileInfo = Self.loadInfoCache()
    }

    // MARK: Access

    func requestAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                Task { @MainActor in self.requestAccess() }
            }
        case .authorized, .limited:
            let wasGranted = access == .granted || access == .limited
            access = status == .limited ? .limited : .granted
            if !observing {
                observing = true
                PHPhotoLibrary.shared().register(self)
            }
            if !wasGranted { reload() }
        default:
            access = .denied
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.version += 1
            self.scheduleReload()
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { reload() }
        }
    }

    // MARK: Fetching

    private var fetchOptions: PHFetchOptions {
        let o = PHFetchOptions()
        o.includeHiddenAssets = config.shouldShowHidden
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return o
    }

    /// Smart albums Fossify shows as folders, in a stable order.
    private static let smartSubtypes: [PHAssetCollectionSubtype] = [
        .smartAlbumUserLibrary, .smartAlbumFavorites, .smartAlbumSelfPortraits, .smartAlbumScreenshots, .smartAlbumVideos,
        .smartAlbumLivePhotos, .smartAlbumDepthEffect, .smartAlbumPanoramas, .smartAlbumBursts, .smartAlbumSlomoVideos,
        .smartAlbumTimelapses, .smartAlbumAnimated, .smartAlbumRAW, .smartAlbumLongExposures,
    ]

    nonisolated private static func collections(includeHidden: Bool) -> [PHAssetCollection] {
        var result: [PHAssetCollection] = []
        var subtypes = smartSubtypes
        if includeHidden { subtypes.append(.smartAlbumAllHidden) }
        for subtype in subtypes {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil).enumerateObjects { c, _, _ in
                result.append(c)
            }
        }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { c, _, _ in
            result.append(c)
        }
        return result
    }

    nonisolated static func path(of c: PHAssetCollection) -> String {
        c.assetCollectionSubtype == .smartAlbumFavorites ? Paths.favorites : c.localIdentifier
    }

    func collection(for path: String) -> PHAssetCollection? {
        if path == Paths.favorites {
            return PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil).firstObject
        }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [path], options: nil).firstObject
    }

    func directoryName(_ path: String) -> String {
        if path.isEmpty || path == Paths.showAll { return "All folders" }
        return allAlbums.first { $0.path == path }?.name ?? collection(for: path)?.localizedTitle ?? ""
    }

    /// getDirectories(): albums with media passing the filters, sorted, pinned first.
    func reload() {
        guard access == .granted || access == .limited else { return }
        let includeHidden = config.shouldShowHidden
        let filter = config.filterMedia
        let excluded = config.temporarilyShowExcluded ? [] : config.excludedFolders
        let covers = config.albumCovers
        let info = fileInfo
        let sortings = Dictionary(uniqueKeysWithValues: Self.collections(includeHidden: includeHidden).map { c in
            (Self.path(of: c), config.folderSorting(Self.path(of: c)))
        })
        Task.detached(priority: .userInitiated) {
            let (dirs, all) = Self.buildDirectories(includeHidden: includeHidden, filter: filter, excluded: excluded,
                                                    covers: covers, info: info, sortings: sortings)
            await MainActor.run {
                self.allAlbums = all
                self.directories = sortDirectories(dirs, config: self.config)
                self.loadedInitial = true
                self.fillFileInfo()
            }
        }
    }

    nonisolated private static func buildDirectories(includeHidden: Bool, filter: Int, excluded: Set<String>, covers: [String: String],
                                                     info: [String: FileInfo], sortings: [String: Int]) -> ([Directory], [Directory]) {
        let options = PHFetchOptions()
        options.includeHiddenAssets = includeHidden
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var dirs: [Directory] = []
        var all: [Directory] = []
        var seen = Set<String>()
        for c in collections(includeHidden: includeHidden) {
            let path = path(of: c)
            guard seen.insert(path).inserted else { continue }
            let result = PHAsset.fetchAssets(in: c, options: options)
            var media: [Medium] = []
            media.reserveCapacity(result.count)
            result.enumerateObjects { a, _, _ in
                let m = Medium(asset: a, info: info[a.localIdentifier], folderName: c.localizedTitle ?? "")
                if m.passes(filter) { media.append(m) }
            }
            let isUser = c.assetCollectionType == .album && c.canPerform(.rename)
            var dir = Directory(path: path, name: c.localizedTitle ?? "", thumbnail: nil, mediaCount: media.count,
                                modified: .distantPast, taken: .distantPast, size: 0, types: 0, isUserAlbum: isUser,
                                isHiddenAlbum: c.assetCollectionSubtype == .smartAlbumAllHidden)
            for m in media {
                dir.size += m.size
                dir.types |= m.type
                if m.modified > dir.modified { dir.modified = m.modified }
                if m.created > dir.taken { dir.taken = m.created }
            }
            if let cover = covers[path], let a = media.first(where: { $0.id == cover }) {
                dir.thumbnail = a.asset
            } else {
                sortMedia(&media, sortings[path] ?? Config.shared.sorting)
                dir.thumbnail = media.first?.asset
            }
            all.append(dir)
            if !media.isEmpty && !excluded.contains(path) { dirs.append(dir) }
        }
        return (dirs, all)
    }

    /// getMediaAsync(): the media of one folder ("" = all folders), filtered and sorted.
    func media(in path: String) async -> [Medium] {
        let includeHidden = config.shouldShowHidden
        let filter = config.filterMedia
        let sorting = config.folderSorting(path.isEmpty ? Paths.showAll : path)
        let info = fileInfo
        let excluded = config.temporarilyShowExcluded ? [] : config.excludedFolders
        let groupsByFolder = path.isEmpty && config.folderGrouping(Paths.showAll) & Grouping.folder != 0
        let collection = path.isEmpty ? nil : collection(for: path)
        return await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.includeHiddenAssets = includeHidden
            var media: [Medium] = []
            if let collection {
                let title = collection.localizedTitle ?? ""
                PHAsset.fetchAssets(in: collection, options: options).enumerateObjects { a, _, _ in
                    media.append(Medium(asset: a, info: info[a.localIdentifier], folderName: title))
                }
            } else if !path.isEmpty {
                return []
            } else {
                // Show all: everything except what only lives in excluded albums.
                var folders: [String: String] = [:]
                var excludedIDs = Set<String>()
                if groupsByFolder || !excluded.isEmpty {
                    PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { c, _, _ in
                        let isExcluded = excluded.contains(c.localIdentifier)
                        PHAsset.fetchAssets(in: c, options: options).enumerateObjects { a, _, _ in
                            if isExcluded { excludedIDs.insert(a.localIdentifier) } else if folders[a.localIdentifier] == nil {
                                folders[a.localIdentifier] = c.localizedTitle ?? ""
                            }
                        }
                    }
                }
                let library = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil).firstObject
                let libraryTitle = library?.localizedTitle ?? "Recents"
                PHAsset.fetchAssets(with: options).enumerateObjects { a, _, _ in
                    let id = a.localIdentifier
                    if excludedIDs.contains(id) && folders[id] == nil { return }
                    media.append(Medium(asset: a, info: info[id], folderName: folders[id] ?? libraryTitle))
                }
            }
            media = media.filter { $0.passes(filter) }
            sortMedia(&media, sorting)
            return media
        }.value
    }

    // MARK: File info cache

    nonisolated private static var infoCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("gallery_file_info.plist")
    }

    nonisolated private static func loadInfoCache() -> [String: FileInfo] {
        guard let data = try? Data(contentsOf: infoCacheURL) else { return [:] }
        return (try? PropertyListDecoder().decode([String: FileInfo].self, from: data)) ?? [:]
    }

    nonisolated static func readInfo(_ a: PHAsset) -> FileInfo? {
        let resources = PHAssetResource.assetResources(for: a)
        let primary = resources.first { [.photo, .video, .fullSizePhoto, .fullSizeVideo].contains($0.type) } ?? resources.first
        guard let r = primary else { return nil }
        let size = (r.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
        return FileInfo(name: r.originalFilename, uti: r.uniformTypeIdentifier, size: size)
    }

    /// Reads names/types/sizes of assets missing from the cache in the background, then refreshes.
    private func fillFileInfo() {
        guard !fillingInfo else { return }
        fillingInfo = true
        let known = fileInfo
        let includeHidden = config.shouldShowHidden
        Task.detached(priority: .utility) {
            let options = PHFetchOptions()
            options.includeHiddenAssets = includeHidden
            var added: [String: FileInfo] = [:]
            var present = Set<String>()
            PHAsset.fetchAssets(with: options).enumerateObjects { a, _, _ in
                present.insert(a.localIdentifier)
                if known[a.localIdentifier] == nil, let info = MediaStore.readInfo(a) { added[a.localIdentifier] = info }
            }
            let added2 = added
            let present2 = present
            await MainActor.run {
                self.fillingInfo = false
                guard !added2.isEmpty else { return }
                self.fileInfo.merge(added2) { _, new in new }
                if !includeHidden || self.fileInfo.count > present2.count * 2 {
                    self.fileInfo = self.fileInfo.filter { present2.contains($0.key) || includeHidden }
                }
                self.saveInfoCache()
                self.version += 1
                self.reload()
            }
        }
    }

    func updateInfo(_ asset: PHAsset) {
        if let info = Self.readInfo(asset) { fileInfo[asset.localIdentifier] = info }
    }

    private func saveInfoCache() {
        let snapshot = fileInfo
        Task.detached(priority: .background) {
            if let data = try? PropertyListEncoder().encode(snapshot) { try? data.write(to: Self.infoCacheURL, options: .atomic) }
        }
    }

    /// Settings > Clear cache.
    func clearCache() {
        imageManager.stopCachingImagesForAllAssets()
        fileInfo = [:]
        try? FileManager.default.removeItem(at: Self.infoCacheURL)
        let tmp = FileManager.default.temporaryDirectory
        for url in (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
        reload()
    }

    var cacheSize: Int64 {
        let fm = FileManager.default
        var total: Int64 = (try? fm.attributesOfItem(atPath: Self.infoCacheURL.path)[.size] as? Int64) ?? 0
        if let e = fm.enumerator(at: fm.temporaryDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in e { total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return total
    }

    // MARK: Changes

    private func perform(_ changes: @escaping () -> Void, success: String? = nil, completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.shared().performChanges(changes) { ok, error in
            Task { @MainActor in
                if ok {
                    if let success { self.toast = success }
                } else if let error = error as NSError?, !(error.domain == PHPhotosErrorDomain && error.code == PHPhotosError.userCancelled.rawValue) {
                    self.toast = error.localizedDescription
                }
                completion?(ok)
            }
        }
    }

    private func assets(_ ids: [String]) -> PHFetchResult<PHAsset> {
        let o = PHFetchOptions()
        o.includeHiddenAssets = true
        return PHAsset.fetchAssets(withLocalIdentifiers: ids, options: o)
    }

    func setFavorite(_ ids: [String], _ on: Bool) {
        let result = assets(ids)
        perform {
            result.enumerateObjects { a, _, _ in PHAssetChangeRequest(for: a).isFavorite = on }
        }
    }

    func setHidden(_ ids: [String], _ hidden: Bool) {
        let result = assets(ids)
        perform {
            result.enumerateObjects { a, _, _ in PHAssetChangeRequest(for: a).isHidden = hidden }
        }
    }

    /// Deletes assets (iOS moves them into Recently Deleted after its own confirmation).
    func delete(_ ids: [String], completion: ((Bool) -> Void)? = nil) {
        let result = assets(ids)
        guard result.count > 0 else { return }
        // Albums that might become empty (Settings > Delete empty folders).
        var albums: [PHAssetCollection] = []
        if config.deleteEmptyFolders {
            result.enumerateObjects { a, _, _ in
                PHAssetCollection.fetchAssetCollectionsContaining(a, with: .album, options: nil).enumerateObjects { c, _, _ in
                    if c.canPerform(.delete) && !albums.contains(c) { albums.append(c) }
                }
            }
        }
        let count = result.count
        perform({ PHAssetChangeRequest.deleteAssets(result) }, success: "Deleting \(count) item\(count == 1 ? "" : "s")") { ok in
            if ok && !albums.isEmpty { self.deleteEmptyAlbums(albums) }
            completion?(ok)
        }
    }

    private func deleteEmptyAlbums(_ albums: [PHAssetCollection]) {
        let o = PHFetchOptions()
        o.includeHiddenAssets = true
        let empty = albums.filter { PHAsset.fetchAssets(in: $0, options: o).count == 0 }
        guard !empty.isEmpty else { return }
        perform { PHAssetCollectionChangeRequest.deleteAssetCollections(empty as NSArray) }
    }

    /// copyMoveFilesTo(): copying adds the assets to the album, moving also removes them from the source album.
    func copyMove(_ ids: [String], to path: String, from source: String?, move: Bool) {
        guard let target = collection(for: path) else { return }
        let result = assets(ids)
        let sourceAlbum = source.flatMap { collection(for: $0) }
        let removeFromSource = move && sourceAlbum?.canPerform(.removeContent) == true
        let n = result.count
        perform({
            if path == Paths.favorites {
                result.enumerateObjects { a, _, _ in PHAssetChangeRequest(for: a).isFavorite = true }
            } else {
                PHAssetCollectionChangeRequest(for: target)?.addAssets(result)
            }
            if removeFromSource, let sourceAlbum {
                if sourceAlbum.assetCollectionSubtype == .smartAlbumFavorites {
                    result.enumerateObjects { a, _, _ in PHAssetChangeRequest(for: a).isFavorite = false }
                } else {
                    PHAssetCollectionChangeRequest(for: sourceAlbum)?.removeAssets(result)
                }
            }
        }, success: move ? "Moving \(n) item\(n == 1 ? "" : "s")" : "Copying \(n) item\(n == 1 ? "" : "s")")
    }

    /// Removes assets from a user album without deleting them.
    func removeFromAlbum(_ ids: [String], path: String) {
        guard let album = collection(for: path), album.canPerform(.removeContent) else { return }
        let result = assets(ids)
        perform { PHAssetCollectionChangeRequest(for: album)?.removeAssets(result) }
    }

    func createAlbum(_ name: String, completion: ((String?) -> Void)? = nil) {
        var placeholder: PHObjectPlaceholder?
        perform({
            placeholder = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name).placeholderForCreatedAssetCollection
        }) { ok in completion?(ok ? placeholder?.localIdentifier : nil) }
    }

    func renameAlbum(_ path: String, to name: String) {
        guard let c = collection(for: path), c.canPerform(.rename) else { return }
        perform { PHAssetCollectionChangeRequest(for: c)?.title = name }
    }

    /// deleteFolders(): deletes the content of the folders and the (user) albums themselves.
    func deleteFolders(_ paths: [String]) {
        let o = PHFetchOptions()
        o.includeHiddenAssets = config.shouldShowHidden
        var ids: [String] = []
        var albums: [PHAssetCollection] = []
        for p in paths {
            guard let c = collection(for: p) else { continue }
            PHAsset.fetchAssets(in: c, options: o).enumerateObjects { a, _, _ in ids.append(a.localIdentifier) }
            if c.canPerform(.delete) { albums.append(c) }
        }
        let result = assets(ids)
        let n = result.count
        perform({
            if n > 0 { PHAssetChangeRequest.deleteAssets(result) }
            if !albums.isEmpty { PHAssetCollectionChangeRequest.deleteAssetCollections(albums as NSArray) }
        }, success: "Deleting \(n) item\(n == 1 ? "" : "s")")
    }

    /// Hide/unhide folder: hides every medium of the album (iOS' Hidden album instead of a .nomedia file).
    func setFolderHidden(_ paths: [String], _ hidden: Bool) {
        let o = PHFetchOptions()
        o.includeHiddenAssets = true
        var ids: [String] = []
        for p in paths {
            guard let c = collection(for: p) else { continue }
            PHAsset.fetchAssets(in: c, options: o).enumerateObjects { a, _, _ in ids.append(a.localIdentifier) }
        }
        setHidden(ids, hidden)
    }

    func folderMediaIDs(_ paths: [String]) -> [String] {
        let o = PHFetchOptions()
        o.includeHiddenAssets = config.shouldShowHidden
        var ids: [String] = []
        for p in paths {
            guard let c = collection(for: p) else { continue }
            PHAsset.fetchAssets(in: c, options: o).enumerateObjects { a, _, _ in ids.append(a.localIdentifier) }
        }
        return ids
    }

    /// Saves a new image into the library (and into the album when given, like saving next to the original).
    func saveNewImage(_ data: Data, album: String?, completion: ((Bool) -> Void)? = nil) {
        let target = album.flatMap { collection(for: $0) }.flatMap { $0.canPerform(.addContent) ? $0 : nil }
        perform({
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, data: data, options: nil)
            if let target, let p = req.placeholderForCreatedAsset {
                PHAssetCollectionChangeRequest(for: target)?.addAssets([p] as NSArray)
            }
        }, completion: completion)
    }

    func saveNewFile(_ url: URL, video: Bool, album: String?, completion: ((Bool) -> Void)? = nil) {
        let target = album.flatMap { collection(for: $0) }.flatMap { $0.canPerform(.addContent) ? $0 : nil }
        perform({
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: video ? .video : .photo, fileURL: url, options: nil)
            if let target, let p = req.placeholderForCreatedAsset {
                PHAssetCollectionChangeRequest(for: target)?.addAssets([p] as NSArray)
            }
        }, completion: completion)
    }

    /// Overwrites an image with an edited rendition (revertible in the Photos app).
    func overwrite(_ asset: PHAsset, with data: Data, description: String, completion: ((Bool) -> Void)? = nil) {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        asset.requestContentEditingInput(with: options) { input, _ in
            guard let input else {
                Task { @MainActor in
                    self.toast = "Could not overwrite the source file"
                    completion?(false)
                }
                return
            }
            let output = PHContentEditingOutput(contentEditingInput: input)
            output.adjustmentData = PHAdjustmentData(formatIdentifier: "org.fossify.gallery", formatVersion: "1",
                                                     data: Data(description.utf8))
            do {
                try data.write(to: output.renderedContentURL, options: .atomic)
            } catch {
                Task { @MainActor in
                    self.toast = "Could not overwrite the source file"
                    completion?(false)
                }
                return
            }
            Task { @MainActor in
                self.perform({ PHAssetChangeRequest(for: asset).contentEditingOutput = output }, completion: completion)
            }
        }
    }

    /// Rotates images by rewriting them (rotateFile / saveRotatedImageToFile).
    func rotate(_ ids: [String], degrees: Int) {
        let result = assets(ids)
        result.enumerateObjects { a, _, _ in
            guard a.mediaType == .image else { return }
            Task { @MainActor in
                guard let data = await ImageLoader.data(for: a), let image = UIImage(data: data),
                      let rotated = image.rotated(degrees: degrees), let jpeg = rotated.jpegData(compressionQuality: 0.95) else { return }
                self.overwrite(a, with: jpeg, description: "rotate \(degrees)")
            }
        }
    }

    /// fixDateTaken(): sets the creation date from the EXIF DateTimeOriginal of each image.
    func fixDateTaken(_ ids: [String]) {
        toast = "Fixing…"
        let result = assets(ids)
        var list: [PHAsset] = []
        result.enumerateObjects { a, _, _ in list.append(a) }
        Task { @MainActor in
            var dates: [(PHAsset, Date)] = []
            for a in list where a.mediaType == .image {
                if let data = await ImageLoader.data(for: a), let date = Exif.dateTaken(data), date != a.creationDate {
                    dates.append((a, date))
                }
            }
            if dates.isEmpty {
                toast = "No Date Taken values have been found"
                return
            }
            perform({
                for (a, date) in dates { PHAssetChangeRequest(for: a).creationDate = date }
            }, success: "Dates fixed successfully")
        }
    }

    /// Resizes images into new files next to the originals (ResizeWithPathDialog / ResizeMultipleImagesDialog).
    func resize(_ ids: [String], factor: Double? = nil, size: CGSize? = nil, album: String?) {
        let result = assets(ids)
        var list: [PHAsset] = []
        result.enumerateObjects { a, _, _ in list.append(a) }
        Task { @MainActor in
            var ok = true
            for a in list where a.mediaType == .image {
                guard let data = await ImageLoader.data(for: a), let image = UIImage(data: data) else { ok = false; continue }
                let target = size ?? CGSize(width: image.size.width * (factor ?? 1), height: image.size.height * (factor ?? 1))
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
                guard let jpeg = resized.jpegData(compressionQuality: 0.95) else { ok = false; continue }
                saveNewImage(jpeg, album: album)
            }
            toast = ok ? (list.count > 1 ? "Images resized successfully" : "File saved successfully") : "Image editing failed"
        }
    }
}

extension UIImage {
    /// Draws the image rotated clockwise by a multiple of 90 degrees.
    func rotated(degrees: Int) -> UIImage? {
        let d = ((degrees % 360) + 360) % 360
        guard d != 0 else { return self }
        let swap = d == 90 || d == 270
        let newSize = swap ? CGSize(width: size.height, height: size.width) : size
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: newSize, format: format).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            c.rotate(by: CGFloat(d) * .pi / 180)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
