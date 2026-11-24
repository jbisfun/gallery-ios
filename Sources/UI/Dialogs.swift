import FossifyCommons
import Photos
import SwiftUI

// MARK: Sorting / grouping / view type / filter

/// ChangeSortingDialog.
struct ChangeSortingDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let isDirectorySorting: Bool
    let showFolderCheckbox: Bool
    var path = ""
    var onChange: () -> Void = {}

    @State private var by = Sort.name
    @State private var descending = false
    @State private var numeric = false
    @State private var useForThisFolder = false
    @State private var initial = 0

    private var pathToUse: String { !isDirectorySorting && path.isEmpty ? Paths.showAll : path }

    private var options: [(Int, String)] {
        var o: [(Int, String)] = [(Sort.name, "Name"), (Sort.path, "Path"), (Sort.size, "Size"), (Sort.dateModified, "Last modified"),
                                  (Sort.dateTaken, "Date taken"), (Sort.random, "Random")]
        if isDirectorySorting {
            o.insert((Sort.count, "Number of items"), at: 3)
            o.append((Sort.custom, "Custom"))
        }
        return o
    }

    var body: some View {
        DialogFrame(title: "Sort by") {
            ForEach(options, id: \.0) { o in
                Button { by = o.0 } label: { RadioRow(title: o.1, on: by == o.0) }.buttonStyle(.plain)
            }
            if by != Sort.custom && by != Sort.random {
                Divider().overlay(palette.divider).padding(.vertical, 8)
                Button { descending = false } label: { RadioRow(title: "Ascending", on: !descending) }.buttonStyle(.plain)
                Button { descending = true } label: { RadioRow(title: "Descending", on: descending) }.buttonStyle(.plain)
            }
            if showFolderCheckbox || by == Sort.name || by == Sort.path {
                Divider().overlay(palette.divider).padding(.vertical, 8)
            }
            if by == Sort.name || by == Sort.path {
                CheckRow(title: "Use numeric value sorting", on: $numeric)
            }
            if showFolderCheckbox {
                CheckRow(title: "Use for this folder only", on: $useForThisFolder)
            }
            if !isDirectorySorting {
                Text("Please note that grouping and sorting are 2 independent fields")
                    .font(.system(size: 14)).foregroundStyle(palette.secondaryText).padding(.top, 8)
            }
            DialogButtons { save() }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let config = Config.shared
        let s = isDirectorySorting ? config.directorySorting : config.folderSorting(pathToUse)
        initial = s
        by = [Sort.path, Sort.size, Sort.count, Sort.dateModified, Sort.dateTaken, Sort.random, Sort.custom].first { s & $0 != 0 } ?? Sort.name
        descending = s & Sort.descending != 0
        numeric = s & Sort.numeric != 0
        useForThisFolder = config.hasCustomSorting(pathToUse)
    }

    private func save() {
        let config = Config.shared
        var s = by
        if descending && by != Sort.custom && by != Sort.random { s |= Sort.descending }
        if numeric && (by == Sort.name || by == Sort.path) { s |= Sort.numeric }
        if isDirectorySorting {
            config.directorySorting = s
        } else if useForThisFolder {
            config.saveCustomSorting(pathToUse, s)
        } else {
            config.removeCustomSorting(pathToUse)
            config.sorting = s
        }
        if s != initial { onChange() }
        dismiss()
    }
}

/// ChangeGroupingDialog.
struct ChangeGroupingDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let path: String
    var onChange: () -> Void = {}
    @State private var by = Grouping.none
    @State private var descending = false
    @State private var showCount = false
    @State private var useForThisFolder = false

    private var pathToUse: String { path.isEmpty ? Paths.showAll : path }

    private var options: [(Int, String)] {
        var o: [(Int, String)] = [(Grouping.none, "Do not group files"), (Grouping.lastModifiedDaily, "Last modified (daily)"),
                                  (Grouping.lastModifiedMonthly, "Last modified (monthly)"), (Grouping.dateTakenDaily, "Date taken (daily)"),
                                  (Grouping.dateTakenMonthly, "Date taken (monthly)"), (Grouping.fileType, "File type"),
                                  (Grouping.ext, "Extension")]
        if path.isEmpty { o.append((Grouping.folder, "Folder")) }
        return o
    }

    var body: some View {
        DialogFrame(title: "Group by") {
            ForEach(options, id: \.0) { o in
                Button { by = o.0 } label: { RadioRow(title: o.1, on: by == o.0) }.buttonStyle(.plain)
            }
            Divider().overlay(palette.divider).padding(.vertical, 8)
            Button { descending = false } label: { RadioRow(title: "Ascending", on: !descending) }.buttonStyle(.plain)
            Button { descending = true } label: { RadioRow(title: "Descending", on: descending) }.buttonStyle(.plain)
            Divider().overlay(palette.divider).padding(.vertical, 8)
            CheckRow(title: "Show file count at section headers", on: $showCount)
            CheckRow(title: "Use for this folder only", on: $useForThisFolder)
            DialogButtons {
                var g = by
                if descending { g |= Grouping.descending }
                if showCount { g |= Grouping.showFileCount }
                let config = Config.shared
                if useForThisFolder {
                    config.saveFolderGrouping(pathToUse, g)
                } else {
                    config.removeFolderGrouping(pathToUse)
                    config.groupBy = g
                }
                onChange()
                dismiss()
            }
        }
        .onAppear {
            let config = Config.shared
            let g = config.folderGrouping(pathToUse)
            by = [Grouping.none, Grouping.lastModifiedDaily, Grouping.lastModifiedMonthly, Grouping.dateTakenDaily, Grouping.dateTakenMonthly,
                  Grouping.fileType, Grouping.ext].first { g & $0 != 0 } ?? Grouping.folder
            descending = g & Grouping.descending != 0
            showCount = g & Grouping.showFileCount != 0
            useForThisFolder = config.hasCustomGrouping(pathToUse)
        }
    }
}

/// ChangeViewTypeDialog.
struct ChangeViewTypeDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let fromFoldersView: Bool
    var path = ""
    @State private var type = ViewType.grid
    @State private var useForThisFolder = false

    private var pathToUse: String { path.isEmpty ? Paths.showAll : path }

    var body: some View {
        DialogFrame(title: "Change view type") {
            Button { type = .grid } label: { RadioRow(title: "Grid", on: type == .grid) }.buttonStyle(.plain)
            Button { type = .list } label: { RadioRow(title: "List", on: type == .list) }.buttonStyle(.plain)
            if !fromFoldersView {
                Divider().overlay(palette.divider).padding(.vertical, 8)
                CheckRow(title: "Use for this folder only", on: $useForThisFolder)
            }
            DialogButtons {
                let config = Config.shared
                if fromFoldersView {
                    config.viewTypeFolders = type
                } else if useForThisFolder {
                    config.saveFolderViewType(pathToUse, type)
                } else {
                    config.removeFolderViewType(pathToUse)
                    config.viewTypeFiles = type
                }
                dismiss()
            }
        }
        .onAppear {
            let config = Config.shared
            type = fromFoldersView ? config.viewTypeFolders : config.folderViewType(pathToUse)
            useForThisFolder = config.hasCustomViewType(pathToUse)
        }
    }
}

/// FilterMediaDialog.
struct FilterMediaDialog: View {
    @Environment(\.dismiss) private var dismiss
    var onChange: () -> Void = {}
    @State private var filter = Config.shared.filterMedia

    var body: some View {
        DialogFrame(title: "Filter media") {
            ForEach(MediaType.all.filter { $0.0 != MediaType.svgs }, id: \.0) { t in
                CheckRow(title: t.1, on: Binding(get: { filter & t.0 != 0 }, set: { filter = $0 ? filter | t.0 : filter & ~t.0 }))
            }
            DialogButtons {
                let result = filter & ~MediaType.svgs == 0 ? MediaType.defaultFilter : filter
                if Config.shared.filterMedia != result {
                    Config.shared.filterMedia = result
                    onChange()
                }
                dismiss()
            }
        }
    }
}

/// Column count chooser (changeColumnCount()).
struct ColumnCountDialog: View {
    let current: Int
    let onPick: (Int) -> Void

    var body: some View {
        RadioDialog(title: nil, items: (1...maxColumnCount).map { ($0, "\($0) column\($0 == 1 ? "" : "s")") }, selected: current, onPick: onPick)
    }
}

// MARK: Thumbnail styles

/// ChangeFileThumbnailStyleDialog.
struct ChangeFileThumbnailStyleDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    private let config = Config.shared
    @State private var rounded = Config.shared.fileRoundedCorners
    @State private var duration = Config.shared.showThumbnailVideoDuration
    @State private var fileTypes = Config.shared.showThumbnailFileTypes
    @State private var favorites = Config.shared.markFavoriteItems
    @State private var spacing = Config.shared.thumbnailSpacing
    @State private var pickSpacing = false

    var body: some View {
        DialogFrame(title: "File thumbnail style") {
            CheckRow(title: "Rounded corners", on: $rounded)
            CheckRow(title: "Show video durations", on: $duration)
            CheckRow(title: "Show image file types", on: $fileTypes)
            CheckRow(title: "Mark favorite items", on: $favorites)
            Button { pickSpacing = true } label: {
                HStack {
                    Text("Thumbnail spacing").foregroundStyle(palette.textColor)
                    Spacer()
                    Text("\(spacing)x").foregroundStyle(palette.secondaryText)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            DialogButtons {
                config.fileRoundedCorners = rounded
                config.showThumbnailVideoDuration = duration
                config.showThumbnailFileTypes = fileTypes
                config.markFavoriteItems = favorites
                config.thumbnailSpacing = spacing
                dismiss()
            }
        }
        .sheet(isPresented: $pickSpacing) {
            RadioDialog(title: nil, items: [0, 1, 2, 4, 8, 16, 32, 64].map { ($0, "\($0)x") }, selected: spacing) { spacing = $0 }
                .environment(\.palette, palette)
        }
    }
}

/// ChangeFolderThumbnailStyleDialog (with its live sample).
struct ChangeFolderThumbnailStyleDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    private let config = Config.shared
    @State private var style = Config.shared.folderStyle
    @State private var count = Config.shared.showFolderMediaCount
    @State private var limit = Config.shared.limitFolderTitle

    var body: some View {
        DialogFrame(title: "Folder thumbnail style") {
            sample.frame(maxWidth: .infinity).padding(.bottom, 12)
            Button { style = .square } label: { RadioRow(title: "Square", on: style == .square) }.buttonStyle(.plain)
            Button { style = .roundedCorners } label: { RadioRow(title: "Rounded corners", on: style == .roundedCorners) }.buttonStyle(.plain)
            Divider().overlay(palette.divider).padding(.vertical, 8)
            Button { count = .line } label: { RadioRow(title: "Show file count on a separate line", on: count == .line) }.buttonStyle(.plain)
            Button { count = .brackets } label: { RadioRow(title: "Show file count in brackets", on: count == .brackets) }.buttonStyle(.plain)
            Button { count = .none } label: { RadioRow(title: "Do not show file count", on: count == .none) }.buttonStyle(.plain)
            Divider().overlay(palette.divider).padding(.vertical, 8)
            CheckRow(title: "Limit long folder titles to 1 line", on: $limit)
            DialogButtons {
                config.folderStyle = style
                config.showFolderMediaCount = count
                config.limitFolderTitle = limit
                dismiss()
            }
        }
    }

    private var sample: some View {
        let name = count == .brackets ? "Camera (36)" : "Camera"
        let image = RoundedRectangle(cornerRadius: style == .roundedCorners ? 16 : 0)
            .fill(LinearGradient(colors: [palette.primaryColor, palette.primaryColor.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "photo.fill").font(.system(size: 40)).foregroundStyle(.white))
            .frame(width: 140, height: 140)
        return Group {
            if style == .square {
                image.overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                        if count == .line { Text("36") }
                    }
                    .font(.system(size: 15)).foregroundStyle(.white).padding(8)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    image
                    Text(name).font(.system(size: 15))
                    if count == .line { Text("36").font(.system(size: 14)).foregroundStyle(palette.secondaryText) }
                }
            }
        }
    }
}

// MARK: Viewer settings dialogs

/// ManageBottomActionsDialog.
struct ManageBottomActionsDialog: View {
    @Environment(\.dismiss) private var dismiss
    @State private var actions = Config.shared.visibleBottomActions

    var body: some View {
        DialogFrame(title: nil) {
            ForEach(BottomAction.available, id: \.rawValue) { a in
                CheckRow(title: a.title, on: Binding(get: { actions & a.rawValue != 0 }, set: { actions = $0 ? actions | a.rawValue : actions & ~a.rawValue }))
            }
            DialogButtons {
                Config.shared.visibleBottomActions = actions
                dismiss()
            }
        }
    }
}

/// ManageExtendedDetailsDialog.
struct ManageExtendedDetailsDialog: View {
    @Environment(\.dismiss) private var dismiss
    @State private var details = Config.shared.extendedDetails

    var body: some View {
        DialogFrame(title: nil) {
            ForEach(ExtendedDetail.allCases, id: \.rawValue) { e in
                CheckRow(title: e.title, on: Binding(get: { details & e.rawValue != 0 }, set: { details = $0 ? details | e.rawValue : details & ~e.rawValue }))
            }
            DialogButtons {
                Config.shared.extendedDetails = details
                dismiss()
            }
        }
    }
}

/// SlideshowDialog.
struct SlideshowDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let onStart: () -> Void
    private let config = Config.shared
    @State private var interval = "\(Config.shared.slideshowInterval)"
    @State private var animation = Config.shared.slideshowAnimation
    @State private var videos = Config.shared.slideshowIncludeVideos
    @State private var gifs = Config.shared.slideshowIncludeGIFs
    @State private var random = Config.shared.slideshowRandomOrder
    @State private var backwards = Config.shared.slideshowMoveBackwards
    @State private var loop = Config.shared.loopSlideshow
    @State private var pickAnimation = false

    var body: some View {
        DialogFrame(title: "Slideshow") {
            HStack {
                Text("Interval").foregroundStyle(palette.textColor)
                Spacer()
                TextField("Seconds", text: $interval)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .foregroundStyle(palette.textColor)
            }
            .padding(.vertical, 10)
            Button { pickAnimation = true } label: {
                HStack {
                    Text("Animation").foregroundStyle(palette.textColor)
                    Spacer()
                    Text(animation.title).foregroundStyle(palette.secondaryText)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            CheckRow(title: "Include videos", on: $videos)
            CheckRow(title: "Include GIFs", on: $gifs)
            CheckRow(title: "Random order", on: $random)
            CheckRow(title: "Move backwards", on: $backwards)
            CheckRow(title: "Loop slideshow", on: $loop)
            DialogButtons {
                let digits = interval.trimmingCharacters(in: CharacterSet(charactersIn: "0").union(.whitespaces))
                config.slideshowInterval = digits.isEmpty ? slideshowDefaultInterval : (Int(interval) ?? slideshowDefaultInterval)
                config.slideshowAnimation = animation
                config.slideshowIncludeVideos = videos
                config.slideshowIncludeGIFs = gifs
                config.slideshowRandomOrder = random
                config.slideshowMoveBackwards = backwards
                config.loopSlideshow = loop
                dismiss()
                onStart()
            }
        }
        .sheet(isPresented: $pickAnimation) {
            RadioDialog(title: nil, items: SlideshowAnimation.allCases.map { ($0, $0.title) }, selected: animation) { animation = $0 }
                .environment(\.palette, palette)
        }
    }
}

// MARK: File operation dialogs

/// DeleteWithRememberDialog (iOS shows its own confirmation afterwards and keeps the items in Recently Deleted).
struct DeleteConfirmDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let message: String
    let onDelete: () -> Void
    @State private var remember = false

    var body: some View {
        DialogFrame(title: nil, scroll: false) {
            Text(message).foregroundStyle(palette.textColor).padding(.bottom, 8)
            CheckRow(title: "Do not ask again in this session", on: $remember)
            HStack(spacing: 24) {
                Spacer()
                Button("No") { dismiss() }
                Button("Yes") {
                    if remember { Config.shared.tempSkipDeleteConfirmation = true }
                    dismiss()
                    onDelete()
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(palette.primaryColor)
            .padding(.top, 16)
        }
        .presentationDetents([.height(220)])
    }
}

/// A one-field dialog (CreateNewFolderDialog / RenameItemDialog for albums).
struct TextInputDialog: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let placeholder: String
    @State var text: String
    let onOK: (String) -> Void

    var body: some View {
        DialogFrame(title: title, scroll: false) {
            DialogTextField(placeholder: placeholder, text: $text)
            DialogButtons(okEnabled: !text.trimmingCharacters(in: .whitespaces).isEmpty) {
                onOK(text.trimmingCharacters(in: .whitespaces))
                dismiss()
            }
        }
        .presentationDetents([.height(200)])
    }
}

/// PickDirectoryDialog: choose a target album (with "Create new folder" and "Other folder").
struct PickDirectoryDialog: View {
    @Environment(MediaStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let title: String
    var exclude: String?
    let onPick: (String) -> Void
    @State private var createFolder = false

    var body: some View {
        let targets = store.allAlbums.filter { ($0.isUserAlbum || $0.areFavorites) && $0.path != exclude }
        DialogFrame(title: title) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(targets) { d in
                    Button {
                        dismiss()
                        onPick(d.path)
                    } label: {
                        DirectoryCell(dir: d, list: false, selected: false, locked: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { createFolder = true } label: {
                Label("Create new folder", systemImage: "folder.badge.plus").padding(.vertical, 12)
            }
            .foregroundStyle(palette.primaryColor)
        }
        .sheet(isPresented: $createFolder) {
            TextInputDialog(title: "Create new folder", placeholder: "Folder name", text: "") { name in
                store.createAlbum(name) { id in
                    if let id {
                        dismiss()
                        onPick(id)
                    }
                }
            }
            .environment(\.palette, palette)
        }
    }
}

/// PickMediumDialog: pick a cover image from the folder.
struct PickMediumDialog: View {
    @Environment(MediaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let path: String
    let onPick: (Medium) -> Void
    @State private var media: [Medium] = []

    var body: some View {
        DialogFrame(title: "Select photo") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4), spacing: 2) {
                ForEach(media) { m in
                    Button {
                        dismiss()
                        onPick(m)
                    } label: {
                        MediumCell(medium: m, list: false, selected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { media = await store.media(in: path).filter { !$0.isVideo } }
    }
}

/// ResizeWithPathDialog: width / height, keeping the aspect ratio.
struct ResizeDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let size: CGSize
    let onResize: (CGSize) -> Void
    @State private var width = ""
    @State private var height = ""
    @State private var keepRatio = true
    @State private var error = false

    var body: some View {
        DialogFrame(title: "Resize selection and save", scroll: false) {
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Width").font(.system(size: 13)).foregroundStyle(palette.secondaryText)
                    DialogTextField(placeholder: "Width", text: $width).keyboardType(.numberPad)
                }
                VStack(alignment: .leading) {
                    Text("Height").font(.system(size: 13)).foregroundStyle(palette.secondaryText)
                    DialogTextField(placeholder: "Height", text: $height).keyboardType(.numberPad)
                }
            }
            CheckRow(title: "Keep aspect ratio", on: $keepRatio)
            if error { Text("Please enter a valid resolution").foregroundStyle(.red).font(.system(size: 14)) }
            DialogButtons {
                guard let w = Int(width), let h = Int(height), w > 0, h > 0 else { error = true; return }
                dismiss()
                onResize(CGSize(width: w, height: h))
            }
        }
        .presentationDetents([.height(300)])
        .onAppear {
            width = "\(Int(size.width))"
            height = "\(Int(size.height))"
        }
        .onChange(of: width) { _, w in
            guard keepRatio, let v = Double(w), size.width > 0 else { return }
            let h = "\(Int((v * size.height / size.width).rounded()))"
            if h != height { height = h }
        }
        .onChange(of: height) { _, hv in
            guard keepRatio, let v = Double(hv), size.height > 0 else { return }
            let w = "\(Int((v * size.width / size.height).rounded()))"
            if w != width { width = w }
        }
    }
}

/// ResizeMultipleImagesDialog: resize factor 10-90%.
struct ResizeMultipleDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let onResize: (Double) -> Void
    @State private var factor = "75"
    @State private var error = false

    var body: some View {
        DialogFrame(title: "Resize multiple images", scroll: false) {
            Text("Resize images to the given percentage, value must be within 10 and 90.").font(.system(size: 14)).foregroundStyle(palette.secondaryText)
            DialogTextField(placeholder: "Resize factor", text: $factor).keyboardType(.numberPad)
            if error { Text("Enter a number between 10 and 90").foregroundStyle(.red).font(.system(size: 14)) }
            DialogButtons {
                guard let f = Int(factor), (10...90).contains(f) else { error = true; return }
                dismiss()
                onResize(Double(f) / 100)
            }
        }
        .presentationDetents([.height(280)])
    }
}

// MARK: Properties

/// PropertiesDialog for media (with EXIF) or folders.
struct PropertiesView: View {
    @Environment(MediaStore.self) private var store
    @Environment(\.palette) private var palette
    let media: [Medium]
    var folders: [Directory] = []
    @State private var rows: [(String, String)] = []

    var body: some View {
        DialogFrame(title: "Properties") {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.0).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.textColor)
                    Text(row.1).font(.system(size: 15)).foregroundStyle(palette.secondaryText).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .contextMenu { Button("Copy") { UIPasteboard.general.string = row.1 } }
            }
            if rows.isEmpty { ProgressView().frame(maxWidth: .infinity) }
        }
        .task { rows = await load() }
    }

    private func load() async -> [(String, String)] {
        let fmt = DateTimeFormat.shared
        if !folders.isEmpty {
            if folders.count == 1, let d = folders.first {
                return [("Name", d.name), ("Path", d.isUserAlbum ? "Albums/\(d.name)" : "Library/\(d.name)"),
                        ("Size", d.size.formattedSize), ("Files count", "\(d.mediaCount)"), ("Last modified", fmt.format(d.modified))]
            }
            return [("Items selected", "\(folders.count)"), ("Size", folders.reduce(Int64(0)) { $0 + $1.size }.formattedSize),
                    ("Files count", "\(folders.reduce(0) { $0 + $1.mediaCount })")]
        }
        if media.count != 1 {
            return [("Items selected", "\(media.count)"), ("Size", media.reduce(Int64(0)) { $0 + $1.size }.formattedSize)]
        }
        let m = media[0]
        let info = MediaStore.readInfo(m.asset)
        var out: [(String, String)] = [("Name", info?.name ?? m.name), ("Path", m.path), ("Size", (info?.size ?? m.size).formattedSize),
                                       ("Resolution", "\(m.width) x \(m.height) (\(megapixels(m)))")]
        if m.isVideo {
            out.append(("Duration", m.duration.formattedDuration()))
        }
        out.append(("Last modified", fmt.format(m.modified)))
        if !m.isVideo, let data = await ImageLoader.data(for: m.asset) {
            let props = Exif.properties(data)
            if let taken = Exif.dateTaken(data) { out.append(("Date taken", fmt.format(taken))) }
            let camera = Exif.cameraModel(props)
            if !camera.isEmpty { out.append(("Camera", camera)) }
            let exif = Exif.exifProperties(props)
            if !exif.isEmpty { out.append(("EXIF", exif)) }
        } else {
            out.append(("Date taken", fmt.format(m.created)))
        }
        if let loc = m.location {
            out.append(("GPS coordinates", String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude)))
            if loc.altitude != 0 { out.append(("Altitude", String(format: "%.0f m", loc.altitude))) }
        }
        return out
    }

    private func megapixels(_ m: Medium) -> String {
        String(format: "%.1fMP", Double(m.width * m.height) / 1_000_000)
    }
}
