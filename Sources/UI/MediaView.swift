import FossifyCommons
import SwiftUI
import UIKit

/// MediaActivity: the thumbnails of one folder ("" = all folders content).
struct MediaView: View {
    @Environment(MediaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let path: String

    @State private var media: [Medium] = []
    @State private var loaded = false
    @State private var query = ""
    @State private var searching = false
    @State private var selected = Set<String>()
    @State private var check: SecurityCheck?

    @State private var showSorting = false
    @State private var showFilter = false
    @State private var showViewType = false
    @State private var showGrouping = false
    @State private var showColumns = false
    @State private var showSlideshow = false
    @State private var createFolder = false
    @State private var camera = false
    @State private var confirmDelete = false
    @State private var properties: [Medium]?
    @State private var copyMove: Bool?
    @State private var share: ShareItems?
    @State private var resizeOne: Medium?
    @State private var resizeMany = false

    private var pathKey: String { path.isEmpty ? Paths.showAll : path }
    private var isShowAllRoot: Bool { path.isEmpty && config.showAll && router.path.isEmpty }
    private var title: String { store.directoryName(path) }
    private var landscape: Bool { isLandscape }

    var body: some View {
        let list = filtered
        let sections = groupMedia(list, grouping: config.folderGrouping(pathKey))
        VStack(spacing: 0) {
            if selected.isEmpty { searchBar } else { selectionBar(list) }
            content(list, sections)
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .task(id: "\(store.version)-\(config.filterMedia)-\(config.shouldShowHidden)-\(config.folderSettingsVersion)-\(config.sorting)") { await load() }
        .securityCheck($check)
        .sheet(isPresented: $showSorting) { ChangeSortingDialog(isDirectorySorting: false, showFolderCheckbox: true, path: path) { Task { await load() } } }
        .sheet(isPresented: $showFilter) { FilterMediaDialog { store.reload() } }
        .sheet(isPresented: $showViewType) { ChangeViewTypeDialog(fromFoldersView: false, path: path) }
        .sheet(isPresented: $showGrouping) { ChangeGroupingDialog(path: path) { Task { await load() } } }
        .sheet(isPresented: $showColumns) {
            ColumnCountDialog(current: config.mediaColumnCount(landscape: landscape)) { config.setMediaColumnCount($0, landscape: landscape) }
        }
        .sheet(isPresented: $showSlideshow) {
            SlideshowDialog {
                if let first = list.first { router.push(.viewer(path: path, id: first.id, only: nil, slideshow: true)) }
            }
        }
        .sheet(isPresented: $createFolder) {
            TextInputDialog(title: "Create new folder", placeholder: "Folder name", text: "") { name in
                store.createAlbum(name) { id in if let id { router.push(.media(id)) } }
            }
        }
        .sheet(item: Binding(get: { properties.map { MediaList(media: $0) } }, set: { properties = $0?.media })) { PropertiesView(media: $0.media) }
        .sheet(item: Binding(get: { copyMove.map { IdentifiedString(value: $0 ? "move" : "copy") } }, set: { copyMove = $0.map { $0.value == "move" } })) { item in
            let move = item.value == "move"
            PickDirectoryDialog(title: move ? "Move to" : "Copy to", exclude: path) { target in
                let ids = Array(selected)
                let run = {
                    store.copyMove(ids, to: target, from: path.isEmpty ? nil : path, move: move)
                    selected.removeAll()
                }
                if move, let c = SecurityCheck.deleteProtection(run) { check = c } else { run() }
            }
        }
        .sheet(item: $share) { ShareSheet(items: $0.urls) }
        .sheet(item: $resizeOne) { m in
            ResizeDialog(size: CGSize(width: m.width, height: m.height)) { size in
                store.resize([m.id], size: size, album: path.isEmpty ? nil : path)
            }
        }
        .sheet(isPresented: $resizeMany) {
            ResizeMultipleDialog { factor in
                store.resize(Array(selected), factor: factor, album: path.isEmpty ? nil : path)
                selected.removeAll()
            }
        }
        .fullScreenCover(isPresented: $camera) { CameraPicker(album: path.isEmpty ? nil : path).ignoresSafeArea() }
        .alert(deleteQuestion, isPresented: $confirmDelete) {
            Button("No", role: .cancel) {}
            Button("Yes") { deleteSelected() }
        }
    }

    private struct MediaList: Identifiable {
        let media: [Medium]
        var id: String { media.map(\.id).joined() }
    }

    private var filtered: [Medium] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return media }
        return media.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func load() async {
        media = await store.media(in: path)
        loaded = true
        selected.formIntersection(media.map(\.id))
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ list: [Medium], _ sections: [MediaSection]) -> some View {
        if list.isEmpty {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !query.isEmpty {
                Placeholder(text: "No items found")
            } else {
                Placeholder(text: "No media files have been found with the selected filters.", action: "Change filters") { showFilter = true }
            }
        } else {
            let isList = config.folderViewType(pathKey) == .list
            let columns = config.mediaColumnCount(landscape: landscape)
            let spacing = CGFloat(config.thumbnailSpacing)
            Group {
                if config.scrollHorizontally || (sections.count == 1 && sections[0].title.isEmpty) {
                    ThumbGrid(items: list, columns: columns, list: isList, horizontal: config.scrollHorizontally, spacing: spacing) { m in cell(m, isList) }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                            ForEach(sections) { section in
                                Text(section.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(palette.primaryColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                if isList {
                                    ForEach(section.media) { cell($0, true) }
                                } else {
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                                        ForEach(section.media) { cell($0, false) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .pinchColumns(columns) { config.setMediaColumnCount($0, landscape: landscape) }
            .refreshable(enabled: config.enablePullToRefresh) { Task { await load() } }
        }
    }

    private func cell(_ m: Medium, _ isList: Bool) -> some View {
        MediumCell(medium: m, list: isList, selected: selected.contains(m.id))
            .onTapGesture { tap(m) }
            .onLongPressGesture { toggle(m) }
    }

    // MARK: Bars

    private var searchBar: some View {
        HStack(spacing: 0) {
            if !isShowAllRoot && !searching {
                IconButton(icon: "arrow.left") { router.pop() }.padding(.leading, 12)
            }
            SearchMenuBar(hint: title.isEmpty ? "Search files" : title, query: $query, searching: $searching, showClose: isShowAllRoot) {
                if config.folderViewType(pathKey) == .grid {
                    IconButton(icon: "textformat") { config.displayFileNames.toggle() }
                }
                if path.isEmpty && config.showAll {
                    IconButton(icon: "folder") { switchToFolderView() }
                }
                IconButton(icon: "camera") { camera = true }
            } menu: {
                Button { showSorting = true } label: { Label("Sort by", systemImage: "arrow.up.arrow.down") }
                Button { showFilter = true } label: { Label("Filter media", systemImage: "line.3.horizontal.decrease") }
                Button { showViewType = true } label: { Label("Change view type", systemImage: "square.grid.2x2") }
                if config.folderViewType(pathKey) == .grid {
                    Button { showColumns = true } label: { Label("Column count", systemImage: "rectangle.split.3x1") }
                }
                Button { showGrouping = true } label: { Label("Group by", systemImage: "rectangle.3.group") }
                if !config.shouldShowHidden {
                    Button { toggleTemporarilyShowHidden() } label: { Label("Temporarily show hidden", systemImage: "eye") }
                } else if config.temporarilyShowHidden {
                    Button { toggleTemporarilyShowHidden() } label: { Label("Stop showing hidden media", systemImage: "eye.slash") }
                }
                if !path.isEmpty {
                    if config.defaultFolder == path {
                        Button { config.defaultFolder = "" } label: { Label("Unset as default folder", systemImage: "folder.badge.minus") }
                    } else {
                        Button { config.defaultFolder = path } label: { Label("Set as default folder", systemImage: "folder.badge.plus") }
                    }
                }
                Button { createFolder = true } label: { Label("Create new folder", systemImage: "folder.badge.plus") }
                Button { showSlideshow = true } label: { Label("Slideshow", systemImage: "play.rectangle") }
                Button { router.push(.settings) } label: { Label("Settings", systemImage: "gearshape") }
                Button { router.push(.about) } label: { Label("About", systemImage: "info.circle") }
            }
        }
    }

    private func selectionBar(_ list: [Medium]) -> some View {
        let sel = list.filter { selected.contains($0.id) }
        let images = sel.filter { $0.isImage || $0.isRaw }
        return SelectionBar(count: selected.count, onClose: { selected.removeAll() }) {
            IconButton(icon: "trash") { askDelete() }
            IconButton(icon: "square.and.arrow.up") { shareSelected(sel) }
            IconButton(icon: "info.circle") { properties = sel }
        } menu: {
            if !images.isEmpty {
                Menu {
                    Button("Rotate right") { rotate(images, 90) }
                    Button("Rotate left") { rotate(images, 270) }
                    Button("Rotate by 180º") { rotate(images, 180) }
                } label: { Label("Rotate", systemImage: "rotate.right") }
            }
            if sel.count == 1, let m = sel.first, !m.isVideo {
                Button {
                    selected.removeAll()
                    router.push(.editor(m.id))
                } label: { Label("Edit", systemImage: "slider.horizontal.3") }
            }
            if sel.contains(where: { !$0.isFavorite }) {
                Button { favorite(sel, true) } label: { Label("Add to favorites", systemImage: "star") }
            }
            if sel.contains(where: \.isFavorite) {
                Button { favorite(sel, false) } label: { Label("Remove from favorites", systemImage: "star.slash") }
            }
            if sel.contains(where: { !$0.isHidden }) {
                Button { hide(sel, true) } label: { Label("Hide", systemImage: "eye.slash") }
            }
            if sel.contains(where: \.isHidden) {
                Button { hide(sel, false) } label: { Label("Unhide", systemImage: "eye") }
            }
            Button { copyMove = false } label: { Label("Copy to", systemImage: "doc.on.doc") }
            Button { copyMove = true } label: { Label("Move to", systemImage: "folder") }
            if !images.isEmpty {
                Button {
                    if images.count == 1 { resizeOne = images[0]; selected.removeAll() } else { resizeMany = true }
                } label: { Label("Resize", systemImage: "arrow.up.left.and.arrow.down.right") }
            }
            if !images.isEmpty {
                Button {
                    store.fixDateTaken(images.map(\.id))
                    selected.removeAll()
                } label: { Label("Fix Date Taken value", systemImage: "calendar.badge.clock") }
            }
            Button { selected = Set(list.map(\.id)) } label: { Label("Select all", systemImage: "checklist") }
        }
    }

    private var deleteQuestion: String {
        let n = selected.count
        return n == 1 ? "Are you sure you want to delete 1 item?" : "Are you sure you want to delete \(n) items?"
    }

    // MARK: Actions

    private func tap(_ m: Medium) {
        guard selected.isEmpty else { toggle(m); return }
        if m.isVideo && config.gestureVideoPlayer {
            router.push(.videoPlayer(m.id))
        } else {
            router.push(.viewer(path: path, id: m.id, only: query.isEmpty ? nil : filtered.map(\.id), slideshow: false))
        }
    }

    private func toggle(_ m: Medium) {
        toggleSelection(m.id, in: &selected)
    }

    private func switchToFolderView() {
        config.showAll = false
    }

    private func toggleTemporarilyShowHidden() {
        if config.temporarilyShowHidden {
            config.temporarilyShowHidden = false
            store.reload()
            return
        }
        let run = {
            config.temporarilyShowHidden = true
            store.reload()
        }
        if let c = StoredProtection.check(.hiddenItems, onSuccess: run) { check = c } else { run() }
    }

    private func askDelete() {
        if config.skipDeleteConfirmation || config.tempSkipDeleteConfirmation { deleteSelected() } else { confirmDelete = true }
    }

    private func deleteSelected() {
        let ids = Array(selected)
        let run = {
            store.delete(ids)
            selected.removeAll()
        }
        if let c = SecurityCheck.deleteProtection(run) { check = c } else { run() }
    }

    private func shareSelected(_ sel: [Medium]) {
        Task { @MainActor in
            var urls: [URL] = []
            for m in sel { if let u = await ImageLoader.exportedFile(for: m) { urls.append(u) } }
            if !urls.isEmpty { share = ShareItems(urls) }
        }
    }

    private func rotate(_ images: [Medium], _ degrees: Int) {
        store.rotate(images.map(\.id), degrees: degrees)
        selected.removeAll()
    }

    private func favorite(_ sel: [Medium], _ on: Bool) {
        store.setFavorite(sel.map(\.id), on)
        selected.removeAll()
    }

    private func hide(_ sel: [Medium], _ on: Bool) {
        store.setHidden(sel.map(\.id), on)
        selected.removeAll()
    }
}
