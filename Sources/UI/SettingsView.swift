import FossifyCommons
import SwiftUI

/// SettingsActivity.
struct SettingsView: View {
    @Environment(MediaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette

    @State private var dateFormat = false
    @State private var loadingPriority = false
    @State private var fileStyle = false
    @State private var folderStyle = false
    @State private var rotation = false
    @State private var extendedDetails = false
    @State private var bottomActions = false
    @State private var check: SecurityCheck?
    @State private var cacheSize: Int64 = 0

    var body: some View {
        @Bindable var config = config
        VStack(spacing: 0) {
            TopBar(title: "Settings")
            ScrollView {
                VStack(spacing: 0) {
                    Text("Color customization").sectionHeader(palette)
                    SettingsItem("Customize colors") { router.push(.customizeColors) }

                    Text("General").sectionHeader(palette)
                    SettingsItem("Change date and time format") { dateFormat = true }
                    SettingsItem("File loading priority", value: config.fileLoadingPriority.title) { loadingPriority = true }
                    SettingsItem("Manage excluded folders") { router.push(.excludedFolders) }
                    SettingsToggle("Show hidden items", isOn: Binding(get: { config.showHiddenMedia }, set: { on in
                        let run = {
                            config.showHiddenMedia = on
                            store.reload()
                        }
                        if on, let c = StoredProtection.check(.hiddenItems, onSuccess: run) { check = c } else { run() }
                    }))
                    SettingsToggle("Search all files instead of folders on the main screen", isOn: $config.searchAllFilesByDefault)

                    Text("Videos").sectionHeader(palette)
                    SettingsToggle("Play videos automatically", isOn: $config.autoplayVideos)
                    SettingsToggle("Remember last video playback position", isOn: $config.rememberLastVideoPosition)
                    SettingsToggle("Loop videos", isOn: $config.loopVideos)
                    SettingsToggle("Play videos on a separate screen with horizontal gestures", isOn: $config.gestureVideoPlayer)
                    SettingsToggle("Allow controlling video volume and brightness with vertical gestures", isOn: $config.allowVideoGestures)

                    Text("Thumbnails").sectionHeader(palette)
                    SettingsToggle("Crop thumbnails into squares", isOn: $config.cropThumbnails)
                    SettingsToggle("Animate GIFs at thumbnails", isOn: $config.animateGifs)
                    SettingsItem("File thumbnail style") { fileStyle = true }
                    SettingsItem("Folder thumbnail style") { folderStyle = true }

                    Text("Scrolling").sectionHeader(palette)
                    SettingsToggle("Scroll thumbnails horizontally", isOn: $config.scrollHorizontally)
                    SettingsToggle("Enable pull-to-refresh from the top", isOn: $config.enablePullToRefresh)

                    Text("Fullscreen media").sectionHeader(palette)
                    SettingsToggle("Max brightness when viewing fullscreen media", isOn: $config.maxBrightness)
                    SettingsToggle("Show Ultra HDR photos in HDR", isOn: $config.ultraHdrRendering)
                    SettingsToggle("Black background at fullscreen media", isOn: $config.blackBackground)
                    SettingsToggle("Automatically hide system UI at fullscreen media", isOn: $config.hideSystemUI)
                    SettingsToggle("Allow instantly changing media by clicking on screen sides", isOn: $config.allowInstantChange)
                    SettingsToggle("Keep the screen on while viewing fullscreen photos", isOn: $config.keepScreenOn)
                    SettingsToggle("Allow controlling photo brightness with vertical gestures", isOn: $config.allowPhotoGestures)
                    SettingsToggle("Allow closing the fullscreen view with a down gesture", isOn: $config.allowDownGesture)
                    SettingsItem("Rotate fullscreen media by", value: config.screenRotation.title) { rotation = true }

                    Text("Deep zoomable images").sectionHeader(palette)
                    SettingsToggle("Allow deep zooming images", isOn: $config.allowZoomingImages)
                    SettingsToggle("Allow rotating images with gestures", isOn: $config.allowRotatingWithGestures)
                    SettingsToggle("Show images in the highest possible quality", isOn: $config.showHighestQuality)
                    SettingsToggle("Allow 1:1 zooming in with two double taps", isOn: $config.allowOneToOneZoom)

                    Text("Extended details").sectionHeader(palette)
                    SettingsToggle("Show extended details over fullscreen media", isOn: $config.showExtendedDetails)
                    if config.showExtendedDetails {
                        SettingsToggle("Hide extended details when status bar is hidden", isOn: $config.hideExtendedDetails)
                        SettingsItem("Manage extended details") { extendedDetails = true }
                    }

                    Text("Security").sectionHeader(palette)
                    PasswordProtectionToggle("Password protect the whole application", kind: .app)
                    StoredProtectionToggle("Password protect hidden item visibility", keys: .hiddenItems)
                    StoredProtectionToggle("Password protect excluded folder visibility", keys: .excluded)
                    PasswordProtectionToggle("Password protect file deletion and moving", kind: .delete)

                    Text("File operations").sectionHeader(palette)
                    SettingsToggle("Delete empty folders after deleting their content", isOn: $config.deleteEmptyFolders)
                    SettingsToggle("Skip delete confirmation dialog", isOn: $config.skipDeleteConfirmation)

                    Text("Bottom actions").sectionHeader(palette)
                    SettingsToggle("Show some action buttons at the bottom of the screen", isOn: $config.bottomActions)
                    if config.bottomActions {
                        SettingsItem("Manage visible bottom actions") { bottomActions = true }
                    }

                    Text("Migrating").sectionHeader(palette)
                    SettingsItem("Clear cache", value: cacheSize.formattedSize) {
                        store.clearCache()
                        cacheSize = store.cacheSize
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .securityCheck($check)
        .onAppear { cacheSize = store.cacheSize }
        .onChange(of: config.scrollHorizontally) { _, _ in store.reload() }
        .sheet(isPresented: $dateFormat) { ChangeDateTimeFormatDialog() }
        .sheet(isPresented: $loadingPriority) {
            RadioDialog(title: nil, items: LoadingPriority.allCases.map { ($0, $0.title) }, selected: config.fileLoadingPriority) { config.fileLoadingPriority = $0 }
        }
        .sheet(isPresented: $rotation) {
            RadioDialog(title: nil, items: Rotation.allCases.map { ($0, $0.title) }, selected: config.screenRotation) { config.screenRotation = $0 }
        }
        .sheet(isPresented: $fileStyle) { ChangeFileThumbnailStyleDialog() }
        .sheet(isPresented: $folderStyle) { ChangeFolderThumbnailStyleDialog() }
        .sheet(isPresented: $extendedDetails) { ManageExtendedDetailsDialog() }
        .sheet(isPresented: $bottomActions) { ManageBottomActionsDialog() }
    }
}

extension AppInfo {
    public static let gallery = AppInfo(name: "Gallery", icon: "photo.on.rectangle", upstream: "Gallery", port: "gallery-ios", policy: "gallery", faq: [
        ("How can I make an album always appear at the top?",
         "You can long press the desired album and select the Pin icon at the actions menu, that will pin it to the top. You can pin multiple folders too, pinned items will be sorted by the default sorting method."),
        ("How can I fast forward videos?",
         "You can do it by double tapping the side of the screen, or tapping the current or max duration texts near the seekbar. If you enable opening videos on a separate screen in the app settings, you can use horizontal gestures too."),
        ("What is the difference between hiding and excluding a folder?",
         "Exclude prevents displaying the folder only in Fossify Gallery, while Hide works system-wise and it hides the media from other galleries too, by moving it into the Hidden album."),
        ("Can I crop images with this app?",
         "Yes, you can crop images in the editor, by dragging the image corners. You can get to the editor either by long pressing an image thumbnail and selecting Edit, or selecting Edit from the fullscreen view."),
        ("Can I somehow group media file thumbnails?",
         "Sure, just use the \"Group by\" menu item while at the thumbnails view. You can group files by multiple criteria, including Date Taken. If you use the \"Show all folders content\" function you can group them by folders too."),
        ("Sorting by Date Taken doesn't seem to work properly, how can I fix it?",
         "It is most likely caused by the files being copied from somewhere. You can fix it by selecting the file thumbnails and selecting \"Fix Date Taken value\"."),
        ("I have hidden a file/folder. How can I unhide it?",
         "You can either press the \"Temporarily show hidden items\" menu item at the main screen, or toggle \"Show hidden items\" in the app settings to see the hidden item. If you want to unhide it, just long press it and select \"Unhide\"."),
    ])
}
