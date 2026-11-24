import FossifyCommons
import Foundation
import Observation

/// Port of the gallery Config (SharedPreferences -> UserDefaults); colors live in FossifyCommons.BaseConfig,
/// password protection in FossifyCommons.PasswordProtection. Keys BaseConfig shares between Fossify apps
/// (sort_order, scroll_horizontally, ...) get a "gallery_" prefix so they don't collide inside the launcher.
@Observable
final class Config {
    static let shared = Config()

    @ObservationIgnored private let d = UserDefaults.standard
    /// Bumped by the per-folder setters so observers of folder sorting / grouping / view type refresh.
    private(set) var folderSettingsVersion = 0

    // Sorting / grouping / view types
    var directorySorting: Int { didSet { d.set(directorySorting, forKey: "directory_sort_order") } }
    var sorting: Int { didSet { d.set(sorting, forKey: "gallery_sort_order") } }
    var groupBy: Int { didSet { d.set(groupBy, forKey: "group_by") } }
    var viewTypeFolders: ViewType { didSet { d.set(viewTypeFolders.rawValue, forKey: "view_type_folders") } }
    var viewTypeFiles: ViewType { didSet { d.set(viewTypeFiles.rawValue, forKey: "view_type_files") } }
    var groupDirectSubfolders: Bool { didSet { d.set(groupDirectSubfolders, forKey: "group_direct_subfolders") } }
    var customFoldersOrder: [String] { didSet { d.set(customFoldersOrder, forKey: "custom_folders_order") } }

    // Main screen
    var showAll: Bool { didSet { d.set(showAll, forKey: "show_all") } }
    var filterMedia: Int { didSet { d.set(filterMedia, forKey: "filter_media") } }
    var defaultFolder: String { didSet { d.set(defaultFolder, forKey: "default_folder") } }
    var pinnedFolders: Set<String> { didSet { d.set(Array(pinnedFolders), forKey: "pinned_folders") } }
    var excludedFolders: Set<String> { didSet { d.set(Array(excludedFolders), forKey: "excluded_folders") } }
    var albumCovers: [String: String] { didSet { d.set(albumCovers, forKey: "album_covers") } }
    var showHiddenMedia: Bool { didSet { d.set(showHiddenMedia, forKey: "show_hidden_media") } }
    var temporarilyShowHidden: Bool { didSet { d.set(temporarilyShowHidden, forKey: "temporarily_show_hidden") } }
    var temporarilyShowExcluded: Bool { didSet { d.set(temporarilyShowExcluded, forKey: "temporarily_show_excluded") } }
    var searchAllFilesByDefault: Bool { didSet { d.set(searchAllFilesByDefault, forKey: "search_all_files_by_default") } }
    var displayFileNames: Bool { didSet { d.set(displayFileNames, forKey: "display_file_names") } }
    var fileLoadingPriority: LoadingPriority { didSet { d.set(fileLoadingPriority.rawValue, forKey: "file_loading_priority") } }

    // Videos
    var autoplayVideos: Bool { didSet { d.set(autoplayVideos, forKey: "autoplay_videos") } }
    var rememberLastVideoPosition: Bool {
        didSet {
            d.set(rememberLastVideoPosition, forKey: "remember_last_video_position")
            if !rememberLastVideoPosition {
                for key in d.dictionaryRepresentation().keys where key.hasPrefix("last_video_position_") { d.removeObject(forKey: key) }
            }
        }
    }
    var loopVideos: Bool { didSet { d.set(loopVideos, forKey: "loop_videos") } }
    var muteVideos: Bool { didSet { d.set(muteVideos, forKey: "mute_videos") } }
    var gestureVideoPlayer: Bool { didSet { d.set(gestureVideoPlayer, forKey: "open_videos_on_separate_screen") } }
    var allowVideoGestures: Bool { didSet { d.set(allowVideoGestures, forKey: "allow_video_gestures") } }
    var playbackSpeed: Float { didSet { d.set(playbackSpeed, forKey: "playback_speed") } }

    // Thumbnails
    var cropThumbnails: Bool { didSet { d.set(cropThumbnails, forKey: "crop_thumbnails") } }
    var animateGifs: Bool { didSet { d.set(animateGifs, forKey: "animate_gifs") } }
    var fileRoundedCorners: Bool { didSet { d.set(fileRoundedCorners, forKey: "file_rounded_corners") } }
    var showThumbnailVideoDuration: Bool { didSet { d.set(showThumbnailVideoDuration, forKey: "show_thumbnail_video_duration") } }
    var showThumbnailFileTypes: Bool { didSet { d.set(showThumbnailFileTypes, forKey: "show_thumbnail_file_types") } }
    var markFavoriteItems: Bool { didSet { d.set(markFavoriteItems, forKey: "mark_favorite_items") } }
    var thumbnailSpacing: Int { didSet { d.set(thumbnailSpacing, forKey: "thumbnail_spacing") } }
    var folderStyle: FolderStyle { didSet { d.set(folderStyle.rawValue, forKey: "folder_thumbnail_style") } }
    var showFolderMediaCount: FolderMediaCount { didSet { d.set(showFolderMediaCount.rawValue, forKey: "folder_media_count") } }
    var limitFolderTitle: Bool { didSet { d.set(limitFolderTitle, forKey: "folder_limit_title") } }

    // Scrolling
    var scrollHorizontally: Bool { didSet { d.set(scrollHorizontally, forKey: "gallery_scroll_horizontally") } }
    var enablePullToRefresh: Bool { didSet { d.set(enablePullToRefresh, forKey: "gallery_enable_pull_to_refresh") } }

    // Fullscreen media
    var maxBrightness: Bool { didSet { d.set(maxBrightness, forKey: "max_brightness") } }
    var ultraHdrRendering: Bool { didSet { d.set(ultraHdrRendering, forKey: "ultra_hdr_rendering") } }
    var blackBackground: Bool { didSet { d.set(blackBackground, forKey: "dark_background") } }
    var hideSystemUI: Bool { didSet { d.set(hideSystemUI, forKey: "hide_system_ui") } }
    var allowInstantChange: Bool { didSet { d.set(allowInstantChange, forKey: "allow_instant_change") } }
    var keepScreenOn: Bool { didSet { d.set(keepScreenOn, forKey: "keep_screen_on") } }
    var allowPhotoGestures: Bool { didSet { d.set(allowPhotoGestures, forKey: "allow_photo_gestures") } }
    var allowDownGesture: Bool { didSet { d.set(allowDownGesture, forKey: "allow_down_gesture") } }
    var screenRotation: Rotation { didSet { d.set(screenRotation.rawValue, forKey: "screen_rotation") } }

    // Deep zoomable images
    var allowZoomingImages: Bool { didSet { d.set(allowZoomingImages, forKey: "allow_zooming_images") } }
    var allowRotatingWithGestures: Bool { didSet { d.set(allowRotatingWithGestures, forKey: "allow_rotating_with_gestures") } }
    var showHighestQuality: Bool { didSet { d.set(showHighestQuality, forKey: "show_highest_quality") } }
    var allowOneToOneZoom: Bool { didSet { d.set(allowOneToOneZoom, forKey: "allow_one_to_one_zoom") } }

    // Extended details
    var showExtendedDetails: Bool { didSet { d.set(showExtendedDetails, forKey: "show_extended_details") } }
    var hideExtendedDetails: Bool { didSet { d.set(hideExtendedDetails, forKey: "hide_extended_details") } }
    var extendedDetails: Int { didSet { d.set(extendedDetails, forKey: "extended_details") } }

    // File operations
    var deleteEmptyFolders: Bool { didSet { d.set(deleteEmptyFolders, forKey: "delete_empty_folders") } }
    var skipDeleteConfirmation: Bool { didSet { d.set(skipDeleteConfirmation, forKey: "gallery_skip_delete_confirmation") } }
    var tempSkipDeleteConfirmation: Bool { didSet { d.set(tempSkipDeleteConfirmation, forKey: "temp_skip_delete_confirmation") } }

    // Bottom actions
    var bottomActions: Bool { didSet { d.set(bottomActions, forKey: "bottom_actions") } }
    var visibleBottomActions: Int { didSet { d.set(visibleBottomActions, forKey: "visible_bottom_actions") } }

    // Slideshow
    var slideshowInterval: Int { didSet { d.set(slideshowInterval, forKey: "slideshow_interval") } }
    var slideshowIncludeVideos: Bool { didSet { d.set(slideshowIncludeVideos, forKey: "slideshow_include_videos") } }
    var slideshowIncludeGIFs: Bool { didSet { d.set(slideshowIncludeGIFs, forKey: "slideshow_include_gifs") } }
    var slideshowRandomOrder: Bool { didSet { d.set(slideshowRandomOrder, forKey: "slideshow_random_order") } }
    var slideshowMoveBackwards: Bool { didSet { d.set(slideshowMoveBackwards, forKey: "slideshow_move_backwards") } }
    var slideshowAnimation: SlideshowAnimation { didSet { d.set(slideshowAnimation.rawValue, forKey: "slideshow_animation") } }
    var loopSlideshow: Bool { didSet { d.set(loopSlideshow, forKey: "loop_slideshow") } }

    // Editor
    var lastEditorCropAspectRatio: Int { didSet { d.set(lastEditorCropAspectRatio, forKey: "last_editor_crop_aspect_ratio") } }
    var lastEditorCropOtherAspectRatioX: Double { didSet { d.set(lastEditorCropOtherAspectRatioX, forKey: "last_editor_crop_other_aspect_ratio_x_2") } }
    var lastEditorCropOtherAspectRatioY: Double { didSet { d.set(lastEditorCropOtherAspectRatioY, forKey: "last_editor_crop_other_aspect_ratio_y_2") } }

    private init() {
        let d = UserDefaults.standard
        func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
        func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
        directorySorting = int("directory_sort_order", Sort.dateModified | Sort.descending)
        sorting = int("gallery_sort_order", Sort.dateModified | Sort.descending | Sort.numeric)
        groupBy = int("group_by", Grouping.none)
        viewTypeFolders = ViewType(rawValue: int("view_type_folders", 1)) ?? .grid
        viewTypeFiles = ViewType(rawValue: int("view_type_files", 1)) ?? .grid
        groupDirectSubfolders = bool("group_direct_subfolders", false)
        customFoldersOrder = d.stringArray(forKey: "custom_folders_order") ?? []
        showAll = bool("show_all", false)
        filterMedia = int("filter_media", MediaType.defaultFilter)
        defaultFolder = d.string(forKey: "default_folder") ?? ""
        pinnedFolders = Set(d.stringArray(forKey: "pinned_folders") ?? [])
        excludedFolders = Set(d.stringArray(forKey: "excluded_folders") ?? [])
        albumCovers = d.dictionary(forKey: "album_covers") as? [String: String] ?? [:]
        showHiddenMedia = bool("show_hidden_media", false)
        temporarilyShowHidden = bool("temporarily_show_hidden", false)
        temporarilyShowExcluded = bool("temporarily_show_excluded", false)
        searchAllFilesByDefault = bool("search_all_files_by_default", false)
        displayFileNames = bool("display_file_names", false)
        fileLoadingPriority = LoadingPriority(rawValue: int("file_loading_priority", 0)) ?? .speed
        autoplayVideos = bool("autoplay_videos", false)
        rememberLastVideoPosition = bool("remember_last_video_position", false)
        loopVideos = bool("loop_videos", false)
        muteVideos = bool("mute_videos", false)
        gestureVideoPlayer = bool("open_videos_on_separate_screen", false)
        allowVideoGestures = bool("allow_video_gestures", true)
        playbackSpeed = d.object(forKey: "playback_speed") as? Float ?? 1
        cropThumbnails = bool("crop_thumbnails", true)
        animateGifs = bool("animate_gifs", false)
        fileRoundedCorners = bool("file_rounded_corners", false)
        showThumbnailVideoDuration = bool("show_thumbnail_video_duration", true)
        showThumbnailFileTypes = bool("show_thumbnail_file_types", true)
        markFavoriteItems = bool("mark_favorite_items", true)
        thumbnailSpacing = int("thumbnail_spacing", 1)
        folderStyle = FolderStyle(rawValue: int("folder_thumbnail_style", 1)) ?? .square
        showFolderMediaCount = FolderMediaCount(rawValue: int("folder_media_count", 1)) ?? .line
        limitFolderTitle = bool("folder_limit_title", false)
        scrollHorizontally = bool("gallery_scroll_horizontally", false)
        enablePullToRefresh = bool("gallery_enable_pull_to_refresh", true)
        maxBrightness = bool("max_brightness", false)
        ultraHdrRendering = bool("ultra_hdr_rendering", true)
        blackBackground = bool("dark_background", true)
        hideSystemUI = bool("hide_system_ui", false)
        allowInstantChange = bool("allow_instant_change", false)
        keepScreenOn = bool("keep_screen_on", true)
        allowPhotoGestures = bool("allow_photo_gestures", false)
        allowDownGesture = bool("allow_down_gesture", true)
        screenRotation = Rotation(rawValue: int("screen_rotation", 0)) ?? .systemSetting
        allowZoomingImages = bool("allow_zooming_images", true)
        allowRotatingWithGestures = bool("allow_rotating_with_gestures", true)
        showHighestQuality = bool("show_highest_quality", false)
        allowOneToOneZoom = bool("allow_one_to_one_zoom", false)
        showExtendedDetails = bool("show_extended_details", false)
        hideExtendedDetails = bool("hide_extended_details", true)
        extendedDetails = int("extended_details", ExtendedDetail.defaults)
        deleteEmptyFolders = bool("delete_empty_folders", false)
        skipDeleteConfirmation = bool("gallery_skip_delete_confirmation", false)
        tempSkipDeleteConfirmation = bool("temp_skip_delete_confirmation", false)
        bottomActions = bool("bottom_actions", true)
        visibleBottomActions = int("visible_bottom_actions", BottomAction.defaults)
        slideshowInterval = int("slideshow_interval", slideshowDefaultInterval)
        slideshowIncludeVideos = bool("slideshow_include_videos", false)
        slideshowIncludeGIFs = bool("slideshow_include_gifs", false)
        slideshowRandomOrder = bool("slideshow_random_order", false)
        slideshowMoveBackwards = bool("slideshow_move_backwards", false)
        slideshowAnimation = SlideshowAnimation(rawValue: int("slideshow_animation", 1)) ?? .slide
        loopSlideshow = bool("loop_slideshow", false)
        lastEditorCropAspectRatio = int("last_editor_crop_aspect_ratio", 0)
        lastEditorCropOtherAspectRatioX = d.object(forKey: "last_editor_crop_other_aspect_ratio_x_2") as? Double ?? 2
        lastEditorCropOtherAspectRatioY = d.object(forKey: "last_editor_crop_other_aspect_ratio_y_2") as? Double ?? 1
    }

    var shouldShowHidden: Bool { showHiddenMedia || temporarilyShowHidden }

    // MARK: Per-folder values (lower-cased path keys, like Android)

    private func key(_ prefix: String, _ path: String) -> String { prefix + path.lowercased() }

    func folderSorting(_ path: String) -> Int {
        _ = folderSettingsVersion
        return d.object(forKey: key("gallery_sort_folder_", path)) as? Int ?? sorting
    }

    func hasCustomSorting(_ path: String) -> Bool { d.object(forKey: key("gallery_sort_folder_", path)) != nil }

    func saveCustomSorting(_ path: String, _ value: Int) {
        if path.isEmpty { sorting = value } else { d.set(value, forKey: key("gallery_sort_folder_", path)) }
        folderSettingsVersion += 1
    }

    func removeCustomSorting(_ path: String) {
        d.removeObject(forKey: key("gallery_sort_folder_", path))
        folderSettingsVersion += 1
    }

    func folderGrouping(_ path: String) -> Int {
        _ = folderSettingsVersion
        var g = d.object(forKey: key("group_folder_", path)) as? Int ?? groupBy
        if path != Paths.showAll && g & Grouping.folder != 0 {
            g -= Grouping.folder + 1
        }
        return g
    }

    func hasCustomGrouping(_ path: String) -> Bool { d.object(forKey: key("group_folder_", path)) != nil }

    func saveFolderGrouping(_ path: String, _ value: Int) {
        if path.isEmpty { groupBy = value } else { d.set(value, forKey: key("group_folder_", path)) }
        folderSettingsVersion += 1
    }

    func removeFolderGrouping(_ path: String) {
        d.removeObject(forKey: key("group_folder_", path))
        folderSettingsVersion += 1
    }

    func folderViewType(_ path: String) -> ViewType {
        _ = folderSettingsVersion
        return ViewType(rawValue: d.object(forKey: key("view_type_folder_", path)) as? Int ?? viewTypeFiles.rawValue) ?? .grid
    }

    func hasCustomViewType(_ path: String) -> Bool { d.object(forKey: key("view_type_folder_", path)) != nil }

    func saveFolderViewType(_ path: String, _ value: ViewType) {
        if path.isEmpty { viewTypeFiles = value } else { d.set(value.rawValue, forKey: key("view_type_folder_", path)) }
        folderSettingsVersion += 1
    }

    func removeFolderViewType(_ path: String) {
        d.removeObject(forKey: key("view_type_folder_", path))
        folderSettingsVersion += 1
    }

    func lastVideoPosition(_ id: String) -> Double { d.double(forKey: key("last_video_position_", id)) }
    func saveLastVideoPosition(_ id: String, _ seconds: Double) { d.set(seconds, forKey: key("last_video_position_", id)) }
    func removeLastVideoPosition(_ id: String) { d.removeObject(forKey: key("last_video_position_", id)) }

    // MARK: Column counts (portrait/landscape x vertical/horizontal scrolling, like Android)

    private func columnsKey(_ prefix: String, landscape: Bool) -> String {
        prefix + (landscape ? "_landscape" : "") + (scrollHorizontally ? "_horizontal" : "") + "_column_cnt"
    }

    func dirColumnCount(landscape: Bool) -> Int {
        _ = folderSettingsVersion
        return d.object(forKey: columnsKey("dir", landscape: landscape)) as? Int ?? (scrollHorizontally ? 3 : 2) * (landscape ? 2 : 1)
    }

    func setDirColumnCount(_ n: Int, landscape: Bool) {
        d.set(n, forKey: columnsKey("dir", landscape: landscape))
        folderSettingsVersion += 1
    }

    func mediaColumnCount(landscape: Bool) -> Int {
        _ = folderSettingsVersion
        return d.object(forKey: columnsKey("media", landscape: landscape)) as? Int ?? (scrollHorizontally ? 4 : 3) * (landscape ? 2 : 1)
    }

    func setMediaColumnCount(_ n: Int, landscape: Bool) {
        d.set(n, forKey: columnsKey("media", landscape: landscape))
        folderSettingsVersion += 1
    }

    func clearAll() {
        folderSettingsVersion += 1
    }
}
