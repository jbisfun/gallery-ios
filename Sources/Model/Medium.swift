import FossifyCommons
import Foundation
import Photos
import UniformTypeIdentifiers

/// What PHAsset can't tell cheaply: the original filename, its type and the file size
/// (read once from PHAssetResource and cached on disk, like Android's media database).
struct FileInfo: Codable, Hashable {
    var name: String
    var uti: String
    var size: Int64
}

/// models/Medium.kt over a PHAsset.
struct Medium: Identifiable, Hashable {
    let asset: PHAsset
    var name: String
    var uti: String
    var size: Int64
    /// Folder (album) the medium was listed from; empty in "show all" / search.
    var folderName: String

    var id: String { asset.localIdentifier }
    var created: Date { asset.creationDate ?? .distantPast }
    var modified: Date { asset.modificationDate ?? asset.creationDate ?? .distantPast }
    var isFavorite: Bool { asset.isFavorite }
    var isHidden: Bool { asset.isHidden }
    var duration: Int { Int(asset.duration.rounded()) }
    var width: Int { asset.pixelWidth }
    var height: Int { asset.pixelHeight }
    var location: CLLocation? { asset.location }

    var isVideo: Bool { asset.mediaType == .video }
    var isGif: Bool { asset.playbackStyle == .imageAnimated || uti == UTType.gif.identifier }
    var isRaw: Bool { UTType(uti)?.conforms(to: .rawImage) ?? false }
    var isPortrait: Bool { asset.mediaSubtypes.contains(.photoDepthEffect) }
    var isImage: Bool { asset.mediaType == .image && !isGif }

    /// TYPE_* bit used by the media filter and grouping by file type.
    var type: Int {
        if isVideo { return MediaType.videos }
        if isGif { return MediaType.gifs }
        if isRaw { return MediaType.raws }
        if isPortrait { return MediaType.portraits }
        return MediaType.images
    }

    var ext: String { (name as NSString).pathExtension.lowercased() }
    var path: String { folderName.isEmpty ? name : "\(folderName)/\(name)" }

    static func == (a: Medium, b: Medium) -> Bool { a.id == b.id && a.asset.modificationDate == b.asset.modificationDate && a.asset.isFavorite == b.asset.isFavorite && a.asset.isHidden == b.asset.isHidden }
    func hash(into h: inout Hasher) { h.combine(id) }

    init(asset: PHAsset, info: FileInfo?, folderName: String) {
        self.asset = asset
        self.folderName = folderName
        if let info {
            name = info.name
            uti = info.uti
            size = info.size
        } else {
            let date = asset.creationDate ?? Date()
            let base = DateTimeFormat.format(date, "yyyyMMdd_HHmmss")
            name = asset.mediaType == .video ? "VID_\(base).mov" : "IMG_\(base).jpg"
            uti = ""
            size = 0
        }
    }

    /// Passes the FILTER_MEDIA bits (portrait photos also pass as plain images).
    func passes(_ filter: Int) -> Bool {
        if isPortrait { return filter & (MediaType.portraits | MediaType.images) != 0 }
        return filter & type != 0
    }
}

/// models/Directory.kt: a PhotoKit album (or smart album) instead of a file system folder.
struct Directory: Identifiable, Hashable {
    /// Album localIdentifier, or Paths.favorites.
    var path: String
    var name: String
    var thumbnail: PHAsset?
    var mediaCount: Int
    var modified: Date
    var taken: Date
    var size: Int64
    var types: Int
    /// User albums can be renamed, deleted and receive copies.
    var isUserAlbum: Bool
    var isHiddenAlbum = false

    var id: String { path }
    var areFavorites: Bool { path == Paths.favorites }

    static func == (a: Directory, b: Directory) -> Bool {
        a.path == b.path && a.name == b.name && a.mediaCount == b.mediaCount && a.thumbnail?.localIdentifier == b.thumbnail?.localIdentifier
            && a.thumbnail?.modificationDate == b.thumbnail?.modificationDate
    }
    func hash(into h: inout Hasher) { h.combine(path) }

    func bubbleText(_ sorting: Int) -> String {
        if sorting & Sort.size != 0 { return size.formattedSize }
        if sorting & Sort.dateModified != 0 { return DateTimeFormat.shared.format(modified) }
        if sorting & Sort.dateTaken != 0 { return DateTimeFormat.shared.format(taken) }
        if sorting & Sort.count != 0 { return "\(mediaCount)" }
        return name
    }
}

// MARK: Sorting (ArrayList<Medium>.sort / Context.getSortedDirectories)

/// String.normalizeString + AlphanumericComparator for SORT_USE_NUMERIC_VALUE.
func compareNames(_ a: String, _ b: String, numeric: Bool) -> ComparisonResult {
    if numeric { return a.localizedStandardCompare(b) }
    return a.localizedCaseInsensitiveCompare(b)
}

func sortMedia(_ media: inout [Medium], _ sorting: Int) {
    if sorting & Sort.random != 0 {
        media.shuffle()
        return
    }
    let numeric = sorting & Sort.numeric != 0
    let desc = sorting & Sort.descending != 0
    media.sort { a, b in
        let r: ComparisonResult
        if sorting & Sort.name != 0 {
            r = compareNames(a.name, b.name, numeric: numeric)
        } else if sorting & Sort.path != 0 {
            r = compareNames(a.path, b.path, numeric: numeric)
        } else if sorting & Sort.size != 0 {
            r = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
        } else if sorting & Sort.dateModified != 0 {
            r = a.modified.compare(b.modified)
        } else {
            r = a.created.compare(b.created)
        }
        if r == .orderedSame { return false }
        return desc ? r == .orderedDescending : r == .orderedAscending
    }
}

func sortDirectories(_ dirs: [Directory], config: Config) -> [Directory] {
    let sorting = config.directorySorting
    var list = dirs
    if sorting & Sort.random != 0 {
        list.shuffle()
    } else if sorting & Sort.custom != 0 {
        let order = Dictionary(config.customFoldersOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        list.sort { (order[$0.path] ?? Int.max, $0.name) < (order[$1.path] ?? Int.max, $1.name) }
    } else {
        let numeric = sorting & Sort.numeric != 0
        let desc = sorting & Sort.descending != 0
        list.sort { a, b in
            let r: ComparisonResult
            if sorting & Sort.name != 0 || sorting & Sort.path != 0 {
                r = compareNames(a.name, b.name, numeric: numeric)
            } else if sorting & Sort.size != 0 {
                r = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            } else if sorting & Sort.count != 0 {
                r = a.mediaCount == b.mediaCount ? .orderedSame : (a.mediaCount < b.mediaCount ? .orderedAscending : .orderedDescending)
            } else if sorting & Sort.dateModified != 0 {
                r = a.modified.compare(b.modified)
            } else {
                r = a.taken.compare(b.taken)
            }
            if r == .orderedSame { return a.name < b.name }
            return desc ? r == .orderedDescending : r == .orderedAscending
        }
    }
    let pinned = list.filter { config.pinnedFolders.contains($0.path) }
    return pinned + list.filter { !config.pinnedFolders.contains($0.path) }
}

// MARK: Grouping (MediaFetcher.groupMedia)

struct MediaSection: Identifiable {
    var title: String
    var media: [Medium]
    var id: String { title }
}

func groupMedia(_ media: [Medium], grouping: Int) -> [MediaSection] {
    guard grouping & Grouping.none == 0 else { return [MediaSection(title: "", media: media)] }
    let showCount = grouping & Grouping.showFileCount != 0
    var order: [String] = []
    var buckets: [String: [Medium]] = [:]
    var sortKeys: [String: String] = [:]
    for m in media {
        let (key, title) = groupKey(m, grouping)
        if buckets[key] == nil {
            order.append(key)
            sortKeys[key] = title
        }
        buckets[key, default: []].append(m)
    }
    let isDate = grouping & (Grouping.lastModifiedDaily | Grouping.lastModifiedMonthly | Grouping.dateTakenDaily | Grouping.dateTakenMonthly) != 0
    let desc = grouping & Grouping.descending != 0
    order.sort { a, b in
        let r = isDate ? a.compare(b) : (sortKeys[a] ?? a).localizedCaseInsensitiveCompare(sortKeys[b] ?? b)
        return desc ? r == .orderedDescending : r == .orderedAscending
    }
    return order.map { key in
        let items = buckets[key] ?? []
        var title = sortKeys[key] ?? key
        if showCount { title += " (\(items.count))" }
        return MediaSection(title: title, media: items)
    }
}

/// (sortable key, header title).
private func groupKey(_ m: Medium, _ grouping: Int) -> (String, String) {
    func day(_ d: Date) -> (String, String) {
        (DateTimeFormat.format(d, "yyyyMMdd"), DateTimeFormat.format(d, DateTimeFormat.shared.dateFormat))
    }
    func month(_ d: Date) -> (String, String) {
        (DateTimeFormat.format(d, "yyyyMM"), DateTimeFormat.format(d, "MMMM yyyy"))
    }
    if grouping & Grouping.lastModifiedDaily != 0 { return day(m.modified) }
    if grouping & Grouping.lastModifiedMonthly != 0 { return month(m.modified) }
    if grouping & Grouping.dateTakenDaily != 0 { return day(m.created) }
    if grouping & Grouping.dateTakenMonthly != 0 { return month(m.created) }
    if grouping & Grouping.fileType != 0 {
        let title: String
        switch m.type {
        case MediaType.videos: title = "Videos"
        case MediaType.gifs: title = "GIFs"
        case MediaType.raws: title = "RAW images"
        case MediaType.portraits: title = "Portraits"
        default: title = "Images"
        }
        return (title, title)
    }
    if grouping & Grouping.ext != 0 { return (m.ext, m.ext.uppercased()) }
    return (m.folderName, m.folderName)
}
