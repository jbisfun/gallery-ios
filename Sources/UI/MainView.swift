import FossifyCommons
import SwiftUI
import UIKit

extension ProtectionKeys {
    /// Gallery's "Password protect excluded folder visibility".
    static let excluded = ProtectionKeys(on: "excluded_password_protection", hash: "excluded_password_hash", type: "excluded_protection_type")
}

/// Grid / list of thumbnails scrolling vertically or horizontally (MyRecyclerView + GridLayoutManager).
struct ThumbGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let columns: Int
    let list: Bool
    let horizontal: Bool
    var spacing: CGFloat = 1
    var bottomPadding: CGFloat = 0
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        if list {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { cell($0) }
                }
                .padding(.bottom, bottomPadding)
            }
        } else if horizontal {
            GeometryReader { geo in
                let side = max((geo.size.height - spacing * CGFloat(columns - 1)) / CGFloat(columns), 10)
                ScrollView(.horizontal) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: columns), spacing: spacing) {
                        ForEach(items) { cell($0).frame(width: side) }
                    }
                }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                    ForEach(items) { cell($0) }
                }
                .padding(.bottom, bottomPadding)
            }
        }
    }
}

/// MainActivity: the folders screen.
struct MainView: View {
    @Environment(MediaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette

    @State private var query = ""
    @State private var searching = false
    @State private var selected = Set<String>()
    @State private var check: SecurityCheck?

    @State private var showSorting = false
    @State private var showFilter = false
    @State private var showViewType = false
    @State private var showColumns = false
    @State private var createFolder = false
    @State private var camera = false
    @State private var properties: [Directory]?
    @State private var rename: Directory?
    @State private var confirmDelete = false
    @State private var confirmExclude = false
    @State private var copyMove: Bool?
    @State private var reorder = false
    @State private var pickCover: Directory?
    @State private var lockFolders: [String]?

    private var landscape: Bool { isLandscape }

    var body: some View {
        let dirs = filteredDirs
        VStack(spacing: 0) {
            if selected.isEmpty { searchBar } else { selectionBar(dirs) }
            content(dirs)
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .securityCheck($check)
        .sheet(isPresented: $showSorting) { ChangeSortingDialog(isDirectorySorting: true, showFolderCheckbox: false) { store.reload() } }
        .sheet(isPresented: $showFilter) { FilterMediaDialog { store.reload() } }
        .sheet(isPresented: $showViewType) { ChangeViewTypeDialog(fromFoldersView: true) }
        .sheet(isPresented: $showColumns) {
            ColumnCountDialog(current: config.dirColumnCount(landscape: landscape)) { config.setDirColumnCount($0, landscape: landscape) }
        }
        .sheet(isPresented: $createFolder) {
            TextInputDialog(title: "Create new folder", placeholder: "Folder name", text: "") { name in
                store.createAlbum(name) { id in if let id { router.push(.media(id)) } }
            }
        }
        .sheet(item: Binding(get: { properties.map { PropertiesItem(dirs: $0) } }, set: { properties = $0?.dirs })) { item in
            PropertiesView(media: [], folders: item.dirs)
        }
        .sheet(item: $rename) { d in
            TextInputDialog(title: "Rename", placeholder: "Folder name", text: d.name) { store.renameAlbum(d.path, to: $0) }
        }
        .sheet(item: Binding(get: { copyMove.map { IdentifiedString(value: $0 ? "move" : "copy") } }, set: { copyMove = $0.map { $0.value == "move" } })) { item in
            let move = item.value == "move"
            PickDirectoryDialog(title: move ? "Move to" : "Copy to", exclude: selected.count == 1 ? selected.first : nil) { target in
                let ids = store.folderMediaIDs(Array(selected))
                let source = selected.count == 1 ? selected.first : nil
                let run = {
                    store.copyMove(ids, to: target, from: source, move: move)
                    selected.removeAll()
                }
                if move, let c = SecurityCheck.deleteProtection(run) { check = c } else { run() }
            }
        }
        .sheet(isPresented: $reorder) { ReorderFoldersDialog(dirs: dirs) }
        .sheet(item: $pickCover) { d in
            PickMediumDialog(path: d.path) { m in
                config.albumCovers[d.path] = m.id
                selected.removeAll()
                store.reload()
            }
        }
        .sheet(item: Binding(get: { lockFolders.map { IdentifiedString(value: $0.joined(separator: "\n")) } }, set: { lockFolders = $0.map { $0.value.components(separatedBy: "\n") } })) { item in
            SecurityDialog(requiredHash: "", showTabIndex: Protection.showAllTabs) { hash, type, ok in
                guard ok else { return }
                for p in item.value.components(separatedBy: "\n") { StoredProtection.set(.folder(p), hash: hash, type: type) }
                selected.removeAll()
            }
        }
        .fullScreenCover(isPresented: $camera) { CameraPicker(album: nil).ignoresSafeArea() }
        .confirm(deleteQuestion, isPresented: $confirmDelete, yes: "Delete", destructive: true) {
            let paths = Array(selected)
            let run = {
                store.deleteFolders(paths)
                selected.removeAll()
            }
            if let c = SecurityCheck.deleteProtection(run) { check = c } else { run() }
        }
        .alert("Exclude", isPresented: $confirmExclude) {
            Button("Cancel", role: .cancel) {}
            Button("OK") {
                config.excludedFolders.formUnion(selected)
                selected.removeAll()
                store.reload()
            }
        } message: {
            Text("This will exclude the selection from Fossify Gallery only. You can manage excluded folders in Settings.")
        }
    }

    private struct PropertiesItem: Identifiable {
        let dirs: [Directory]
        var id: String { dirs.map(\.path).joined() }
    }

    private var filteredDirs: [Directory] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.directories }
        return store.directories.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    @ViewBuilder
    private func content(_ dirs: [Directory]) -> some View {
        if dirs.isEmpty {
            if !store.loadedInitial {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !query.isEmpty {
                Placeholder(text: "No items found")
            } else if config.filterMedia != MediaType.defaultFilter {
                Placeholder(text: "No media files have been found with the selected filters.", action: "Change filters") { showFilter = true }
            } else {
                Placeholder(text: store.access == .limited ? "No items found. Gallery only has access to the photos you selected." : "No items found",
                            action: store.access == .limited ? "Open settings" : nil) {
                    Launcher.open(URL(string: UIApplication.openSettingsURLString))
                }
            }
        } else {
            let list = config.viewTypeFolders == .list
            let columns = config.dirColumnCount(landscape: landscape)
            ThumbGrid(items: dirs, columns: columns, list: list, horizontal: config.scrollHorizontally,
                      spacing: config.folderStyle == .roundedCorners ? 8 : 1) { d in
                DirectoryCell(dir: d, list: list, selected: selected.contains(d.path), locked: StoredProtection.isOn(.folder(d.path)))
                    .onTapGesture { tap(d) }
                    .onLongPressGesture { toggle(d) }
            }
            .padding(.horizontal, config.folderStyle == .roundedCorners && !list ? 8 : 0)
            .pinchColumns(columns) { config.setDirColumnCount($0, landscape: landscape) }
            .refreshable(enabled: config.enablePullToRefresh) { store.reload() }
        }
    }

    // MARK: Bars

    private var searchBar: some View {
        SearchMenuBar(hint: "Search folders", query: $query, searching: $searching,
                      onTapSearch: config.searchAllFilesByDefault ? { router.push(.search) } : nil) {
            IconButton(icon: "camera") { camera = true }
            IconButton(icon: "photo.on.rectangle") { showAll() }
        } menu: {
            Button { showSorting = true } label: { Label("Sort by", systemImage: "arrow.up.arrow.down") }
            Button { showFilter = true } label: { Label("Filter media", systemImage: "line.3.horizontal.decrease") }
            Button { showViewType = true } label: { Label("Change view type", systemImage: "square.grid.2x2") }
            if config.viewTypeFolders == .grid {
                Button { showColumns = true } label: { Label("Column count", systemImage: "rectangle.split.3x1") }
            }
            if !config.shouldShowHidden {
                Button { toggleTemporarilyShowHidden() } label: { Label("Temporarily show hidden", systemImage: "eye") }
            } else if config.temporarilyShowHidden {
                Button { toggleTemporarilyShowHidden() } label: { Label("Stop showing hidden media", systemImage: "eye.slash") }
            }
            if config.temporarilyShowExcluded {
                Button { toggleTemporarilyShowExcluded() } label: { Label("Stop showing excluded", systemImage: "eye.slash") }
            } else {
                Button { toggleTemporarilyShowExcluded() } label: { Label("Temporarily show excluded", systemImage: "eye") }
            }
            if !config.defaultFolder.isEmpty {
                Button { config.defaultFolder = "" } label: { Label("Unset as default folder", systemImage: "folder.badge.minus") }
            }
            Button { createFolder = true } label: { Label("Create new folder", systemImage: "folder.badge.plus") }
            Button { router.push(.settings) } label: { Label("Settings", systemImage: "gearshape") }
            Button { router.push(.about) } label: { Label("About", systemImage: "info.circle") }
        }
    }

    private func selectionBar(_ dirs: [Directory]) -> some View {
        let sel = dirs.filter { selected.contains($0.path) }
        let allPinned = sel.allSatisfy { config.pinnedFolders.contains($0.path) }
        let userAlbums = sel.filter(\.isUserAlbum)
        return SelectionBar(count: selected.count, onClose: { selected.removeAll() }) {
            IconButton(icon: "trash") { confirmDelete = true }
            IconButton(icon: "info.circle") { properties = sel }
            IconButton(icon: allPinned ? "pin.slash" : "pin") {
                if allPinned { config.pinnedFolders.subtract(selected) } else { config.pinnedFolders.formUnion(selected) }
                selected.removeAll()
                store.reload()
            }
        } menu: {
            Button { reorder = true; selected.removeAll() } label: { Label("Reorder folders by dragging", systemImage: "arrow.up.arrow.down") }
            if sel.count == 1, let d = sel.first, d.isUserAlbum {
                Button { rename = d; selected.removeAll() } label: { Label("Rename", systemImage: "pencil") }
            }
            if sel.contains(where: { !$0.isHiddenAlbum }) {
                Button { hideFolders(true) } label: { Label("Hide folder", systemImage: "eye.slash") }
            }
            if config.shouldShowHidden {
                Button { hideFolders(false) } label: { Label("Unhide folder", systemImage: "eye") }
            }
            Button { confirmExclude = true } label: { Label("Exclude", systemImage: "minus.circle") }
            if sel.contains(where: { !StoredProtection.isOn(.folder($0.path)) }) {
                Button { lockFolders = sel.map(\.path) } label: { Label("Lock folder", systemImage: "lock") }
            }
            if sel.contains(where: { StoredProtection.isOn(.folder($0.path)) }) {
                Button { unlockFolders(sel) } label: { Label("Unlock folder", systemImage: "lock.open") }
            }
            Button { copyMove = false } label: { Label("Copy to", systemImage: "doc.on.doc") }
            if !userAlbums.isEmpty {
                Button { copyMove = true } label: { Label("Move to", systemImage: "folder") }
            }
            if sel.count == 1, let d = sel.first {
                Menu {
                    Button("Select photo") { pickCover = d }
                    Button("Use default") {
                        config.albumCovers[d.path] = nil
                        selected.removeAll()
                        store.reload()
                    }
                } label: { Label("Change cover image", systemImage: "photo") }
            }
            Button { selected = Set(dirs.map(\.path)) } label: { Label("Select all", systemImage: "checklist") }
        }
    }

    private var deleteQuestion: String {
        let n = selected.count
        let items = store.directories.filter { selected.contains($0.path) }.reduce(0) { $0 + $1.mediaCount }
        return "Are you sure you want to delete \(n) folder\(n == 1 ? "" : "s") with \(items) item\(items == 1 ? "" : "s")?"
    }

    // MARK: Actions

    private func tap(_ d: Directory) {
        guard selected.isEmpty else { toggle(d); return }
        if let c = StoredProtection.check(.folder(d.path), onSuccess: { router.push(.media(d.path)) }) {
            check = c
        } else {
            router.push(.media(d.path))
        }
    }

    private func toggle(_ d: Directory) {
        toggleSelection(d.path, in: &selected)
    }

    private func showAll() {
        config.showAll = true
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

    private func toggleTemporarilyShowExcluded() {
        if config.temporarilyShowExcluded {
            config.temporarilyShowExcluded = false
            store.reload()
            return
        }
        let run = {
            config.temporarilyShowExcluded = true
            store.reload()
        }
        if let c = StoredProtection.check(.excluded, onSuccess: run) { check = c } else { run() }
    }

    private func hideFolders(_ hide: Bool) {
        store.setFolderHidden(Array(selected), hide)
        selected.removeAll()
    }

    private func unlockFolders(_ sel: [Directory]) {
        let locked = sel.filter { StoredProtection.isOn(.folder($0.path)) }
        guard let first = locked.first else { return }
        check = StoredProtection.check(.folder(first.path)) {
            for d in locked { StoredProtection.clear(.folder(d.path)) }
            selected.removeAll()
        }
    }
}

/// Drag-and-drop folder ordering (cab_change_order), stored as the custom sorting.
struct ReorderFoldersDialog: View {
    @Environment(MediaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State var dirs: [Directory]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Reorder folders by dragging").font(.system(size: 19, weight: .medium))
                Spacer()
            }
            .padding(20)
            List {
                ForEach(dirs) { d in
                    DirectoryCell(dir: d, list: true, selected: false, locked: false, dragging: true)
                        .listRowBackground(palette.surface)
                        .listRowInsets(EdgeInsets())
                }
                .onMove { dirs.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            HStack(spacing: 24) {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("OK") {
                    let config = Config.shared
                    config.customFoldersOrder = dirs.map(\.path)
                    config.directorySorting = Sort.custom
                    store.reload()
                    dismiss()
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(palette.primaryColor)
            .padding(20)
        }
        .background(palette.surface.ignoresSafeArea())
    }
}

extension View {
    /// SwipeRefreshLayout, only when "Enable pull-to-refresh" is on.
    @ViewBuilder
    func refreshable(enabled: Bool, _ action: @escaping @MainActor () -> Void) -> some View {
        if enabled {
            self.refreshable { action() }
        } else {
            self
        }
    }
}
