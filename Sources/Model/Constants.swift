import Foundation

/// helpers/Constants.kt plus the Fossify Commons sorting / view type constants it uses.
enum Sort {
    static let name = 1
    static let dateModified = 2
    static let size = 4
    static let dateTaken = 8
    static let path = 32
    static let descending = 1024
    static let random = 16384
    static let numeric = 32768
    static let custom = 131072
    static let count = 524288
}

enum ViewType: Int {
    case grid = 1, list = 2
}

/// Media types (FILTER_MEDIA bits).
enum MediaType {
    static let images = 1
    static let videos = 2
    static let gifs = 4
    static let raws = 8
    static let svgs = 16
    static let portraits = 32
    static let defaultFilter = images | videos | gifs | raws | svgs

    static let all: [(Int, String)] = [(images, "Images"), (videos, "Videos"), (gifs, "GIFs"),
                                       (raws, "RAW images"), (svgs, "SVGs"), (portraits, "Portraits")]
}

enum Grouping {
    static let none = 1
    static let lastModifiedDaily = 2
    static let dateTakenDaily = 4
    static let fileType = 8
    static let ext = 16
    static let folder = 32
    static let lastModifiedMonthly = 64
    static let dateTakenMonthly = 128
    static let descending = 1024
    static let showFileCount = 2048
}

enum BottomAction: Int, CaseIterable {
    case toggleFavorite = 1, edit = 2, share = 4, delete = 8, rotate = 16, properties = 32, changeOrientation = 64,
         slideshow = 128, showOnMap = 256, toggleVisibility = 512, rename = 1024, setAs = 2048, copy = 4096,
         move = 8192, resize = 16384

    static let defaults = toggleFavorite.rawValue | edit.rawValue | share.rawValue | delete.rawValue

    /// The ones iOS can do (rename / set as wallpaper have no API).
    static let available: [BottomAction] = [.toggleFavorite, .edit, .share, .delete, .rotate, .properties, .changeOrientation,
                                            .slideshow, .showOnMap, .toggleVisibility, .copy, .move, .resize]

    var title: String {
        switch self {
        case .toggleFavorite: return "Toggle favorite"
        case .edit: return "Edit"
        case .share: return "Share"
        case .delete: return "Delete"
        case .rotate: return "Rotate"
        case .properties: return "Properties"
        case .changeOrientation: return "Change orientation"
        case .slideshow: return "Slideshow"
        case .showOnMap: return "Show on map"
        case .toggleVisibility: return "Toggle file visibility"
        case .rename: return "Rename"
        case .setAs: return "Set as"
        case .copy: return "Copy to"
        case .move: return "Move to"
        case .resize: return "Resize"
        }
    }
}

enum ExtendedDetail: Int, CaseIterable {
    case name = 1, path = 2, size = 4, resolution = 8, lastModified = 16, dateTaken = 32, cameraModel = 64,
         exifProperties = 128, gps = 2048

    static let defaults = resolution.rawValue | lastModified.rawValue | exifProperties.rawValue

    var title: String {
        switch self {
        case .name: return "Name"
        case .path: return "Path"
        case .size: return "Size"
        case .resolution: return "Resolution"
        case .lastModified: return "Last modified"
        case .dateTaken: return "Date taken"
        case .cameraModel: return "Camera"
        case .exifProperties: return "EXIF"
        case .gps: return "GPS coordinates"
        }
    }
}

enum Rotation: Int, CaseIterable {
    case systemSetting = 0, deviceRotation, aspectRatio

    var title: String {
        switch self {
        case .systemSetting: return "System setting"
        case .deviceRotation: return "Device rotation"
        case .aspectRatio: return "Aspect ratio"
        }
    }
}

enum LoadingPriority: Int, CaseIterable {
    case speed = 0, compromise, validity

    var title: String {
        switch self {
        case .speed: return "Speed"
        case .compromise: return "Compromise"
        case .validity: return "Avoid showing invalid files"
        }
    }
}

enum SlideshowAnimation: Int, CaseIterable {
    case none = 0, slide, fade

    var title: String {
        switch self {
        case .none: return "None"
        case .slide: return "Slide"
        case .fade: return "Fade"
        }
    }
}

enum FolderMediaCount: Int {
    case line = 1, brackets, none
}

enum FolderStyle: Int {
    case square = 1, roundedCorners
}

/// Pseudo folder paths.
enum Paths {
    static let showAll = "show_all"
    static let favorites = "favorites"
    static let recents = "recents"
}

let maxColumnCount = 20
let slideshowDefaultInterval = 5
