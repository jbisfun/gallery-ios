import FossifyCommons
import Photos
import SwiftUI

/// MyWidgetProvider + WidgetConfigureActivity: the folder widget (a folder's thumbnail with its name),
/// drawn by launcher-ios on its home grid. Tapping it opens the app (MediaActivity of the folder upstream).
public enum GalleryWidgets {
    public static let all: [HomeWidgetKind] = [
        HomeWidgetKind(
            id: "gallery.folder", title: "Gallery folder",
            // widget_info.xml: targetCell 2x1, minResize 40dp, resizeMode horizontal|vertical.
            defaultSize: CGSize(width: 2, height: 1), minSize: CGSize(width: 1, height: 1), resizable: true,
            configure: { context, done in AnyView(FolderWidgetConfigure(context: context, done: done)) },
            content: { context in AnyView(FolderWidget(context: context)) }
        ),
    ]
}

// MARK: Settings

/// Per-widget settings (the Widget row of widgetsDB plus the colors/folder-name switch upstream keeps in Config).
/// The last saved values seed the next configure screen, like upstream's Config.widget* values.
enum FolderWidgetSettings {
    static let defaultBgColor: UInt32 = 0xAA000000 // default_widget_bg_color
    static let defaultTextColor: UInt32 = 0xFF106D1F // default_widget_text_color (color_primary)

    static let lastBgKey = "gallery_widget_bg_color"
    static let lastTextKey = "gallery_widget_text_color"
    static let lastShowNameKey = "gallery_show_widget_folder_name"

    static var lastBgColor: UInt32 { color(lastBgKey) ?? defaultBgColor }
    static var lastTextColor: UInt32 { color(lastTextKey) ?? defaultTextColor }
    static var lastShowName: Bool { UserDefaults.standard.object(forKey: lastShowNameKey) as? Bool ?? true }

    static func color(_ key: String) -> UInt32? {
        (UserDefaults.standard.object(forKey: key) as? Int).map { UInt32(truncatingIfNeeded: $0) }
    }
}

@MainActor
extension MediaStore {
    /// The store behind every gallery widget: observes the photo library, so widgets follow new, deleted
    /// and favorited media like the app does.
    static let widgets = MediaStore()

    /// Starts loading when the library is already accessible (widgets never trigger the permission prompt).
    func startForWidgets() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { requestAccess() }
    }
}

/// Config values that change folder thumbnails; widgets reload when one of them changes.
private func thumbnailSettingsKey(_ c: Config) -> String {
    "\(c.albumCovers.sorted { $0.key < $1.key })|\(c.folderSettingsVersion)|\(c.sorting)|\(c.filterMedia)|\(c.shouldShowHidden)|\(c.excludedFolders.sorted())"
}

// MARK: Widget

/// widget.xml: rounded background, the folder thumbnail and an optional one-line folder name.
struct FolderWidget: View {
    let context: HomeWidgetContext
    @State private var store = MediaStore.widgets
    @Environment(\.scenePhase) private var phase
    @AppStorage private var folder: String
    @AppStorage private var bgColor: Int
    @AppStorage private var textColor: Int
    @AppStorage private var showName: Bool

    init(context: HomeWidgetContext) {
        self.context = context
        _folder = AppStorage(wrappedValue: "", context.key("folder_path"))
        _bgColor = AppStorage(wrappedValue: Int(FolderWidgetSettings.lastBgColor), context.key("bg_color"))
        _textColor = AppStorage(wrappedValue: Int(FolderWidgetSettings.lastTextColor), context.key("text_color"))
        _showName = AppStorage(wrappedValue: FolderWidgetSettings.lastShowName, context.key("show_folder_name"))
    }

    var body: some View {
        let config = Config.shared
        FolderWidgetBody(asset: store.allAlbums.first { $0.path == folder }?.thumbnail,
                         name: store.directoryName(folder),
                         crop: config.cropThumbnails,
                         bgColor: UInt32(truncatingIfNeeded: bgColor),
                         textColor: UInt32(truncatingIfNeeded: textColor),
                         showName: showName)
            .environment(store)
            .contentShape(Rectangle())
            .onTapGesture { context.openApp(nil) }
            .onAppear { store.startForWidgets() }
            .onChange(of: phase) { _, p in if p == .active { store.startForWidgets() } }
            .onChange(of: thumbnailSettingsKey(config)) { _, _ in store.reload() }
    }
}

/// The widget look, shared by the home grid and the configure preview.
struct FolderWidgetBody: View {
    let asset: PHAsset?
    let name: String
    let crop: Bool
    let bgColor: UInt32
    let textColor: UInt32
    let showName: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Upstream loads a max(w, h) square bitmap (center-cropped with "Crop thumbnails")
            // and fits it into the image view.
            Group {
                if crop {
                    Thumbnail(asset: asset, crop: true).aspectRatio(1, contentMode: .fit)
                } else {
                    Thumbnail(asset: asset, crop: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
            if showName {
                Text(name)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(argb: textColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .padding(2)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(argb: bgColor)))
    }
}

// MARK: Configure

/// activity_widget_config.xml: folder name switch, folder picker, preview, background color + alpha,
/// text color and OK.
struct FolderWidgetConfigure: View {
    let context: HomeWidgetContext
    let done: (Bool) -> Void

    var body: some View {
        FolderWidgetConfigureContent(context: context, done: done)
            .environment(MediaStore.widgets)
            .environment(Config.shared)
            .fossifyTheme()
    }
}

private struct FolderWidgetConfigureContent: View {
    let context: HomeWidgetContext
    let done: (Bool) -> Void
    @Environment(MediaStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette

    @State private var folder = ""
    @State private var bgColor: UInt32 = 0 // without transparency
    @State private var bgAlpha = 0.0
    @State private var textColor: UInt32 = 0
    @State private var showName = true
    @State private var loaded = false
    @State private var pickFolder = false
    @State private var pickBg = false
    @State private var pickText = false

    private var effectiveBg: UInt32 { UInt32((bgAlpha * 255).rounded()) << 24 | (bgColor & 0xFFFFFF) }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Gallery folder", onBack: { done(false) })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsToggle("Show folder name", isOn: $showName)
                    Text("Folder on widget:")
                        .foregroundStyle(palette.textColor)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    Button { pickFolder = true } label: {
                        Text(folder.isEmpty ? " " : store.directoryName(folder))
                            .foregroundStyle(palette.textColor)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(palette.textColor.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 16)
                    .padding(.bottom, 16)

                    Button { pickFolder = true } label: {
                        FolderWidgetBody(asset: store.allAlbums.first { $0.path == folder }?.thumbnail,
                                         name: store.directoryName(folder), crop: config.cropThumbnails,
                                         bgColor: effectiveBg, textColor: textColor, showName: showName)
                            .frame(width: 160, height: 110 + 8 + (showName ? 24 : 0))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }
                .padding(16)
            }
            colorsBar
        }
        .paletteBackground()
        .onAppear(perform: load)
        .onChange(of: store.directories) { _, dirs in
            // getCachedDirectories(): preselect the first folder.
            if folder.isEmpty, let first = dirs.first { folder = first.path }
        }
        .sheet(isPresented: $pickFolder) {
            WidgetFolderPicker { folder = $0 }.environment(\.palette, palette)
        }
        .sheet(isPresented: $pickBg) {
            ColorPickerDialog(color: bgColor) { bgColor = $0 & 0xFFFFFF | 0xFF000000 }
        }
        .sheet(isPresented: $pickText) {
            ColorPickerDialog(color: textColor) { textColor = $0 }
        }
    }

    private var colorsBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                swatch(effectiveBg) { pickBg = true }
                Slider(value: $bgAlpha, in: 0...1)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity)
                    .background(Capsule().fill(palette.textColor.opacity(0.1)))
            }
            .frame(height: 50)
            HStack {
                swatch(textColor) { pickText = true }
                Spacer()
                Button(action: save) {
                    Text("OK")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.onPrimary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(palette.primaryColor))
                }
            }
        }
        .padding(16)
    }

    private func swatch(_ color: UInt32, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(argb: color))
                .overlay(Circle().stroke(Color(argb: color | 0xFF000000), lineWidth: 2))
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let d = UserDefaults.standard
        let bg = FolderWidgetSettings.color(context.key("bg_color")) ?? FolderWidgetSettings.lastBgColor
        bgColor = bg | 0xFF000000
        bgAlpha = Double(bg >> 24) / 255
        textColor = FolderWidgetSettings.color(context.key("text_color")) ?? FolderWidgetSettings.lastTextColor
        showName = d.object(forKey: context.key("show_folder_name")) as? Bool ?? FolderWidgetSettings.lastShowName
        folder = d.string(forKey: context.key("folder_path")) ?? ""
        store.requestAccess()
        if folder.isEmpty, let first = store.directories.first { folder = first.path }
    }

    /// saveConfig(): stores the widget's folder and colors.
    private func save() {
        let d = UserDefaults.standard
        d.set(folder, forKey: context.key("folder_path"))
        d.set(Int(effectiveBg), forKey: context.key("bg_color"))
        d.set(Int(textColor), forKey: context.key("text_color"))
        d.set(showName, forKey: context.key("show_folder_name"))
        d.set(Int(effectiveBg), forKey: FolderWidgetSettings.lastBgKey)
        d.set(Int(textColor), forKey: FolderWidgetSettings.lastTextKey)
        d.set(showName, forKey: FolderWidgetSettings.lastShowNameKey)
        done(true)
    }
}

/// PickDirectoryDialog(isPickingFolderForWidget = true): every shown folder, favorites included.
private struct WidgetFolderPicker: View {
    @Environment(MediaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    var body: some View {
        DialogFrame(title: "Select a folder") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(store.directories) { d in
                    Button {
                        dismiss()
                        onPick(d.path)
                    } label: {
                        DirectoryCell(dir: d, list: false, selected: false, locked: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .environment(Config.shared)
        .environment(store)
    }
}
