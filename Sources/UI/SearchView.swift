import FossifyCommons
import SwiftUI

/// SearchActivity: file search across all visible folders.
struct SearchView: View {
    @Environment(MediaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @State private var all: [Medium] = []
    @State private var query = ""
    @State private var searching = true
    @FocusState private var focused: Bool

    private var results: [Medium] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return all.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        let list = results
        let isList = config.folderViewType(Paths.showAll) == .list
        let columns = config.mediaColumnCount(landscape: isLandscape)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                IconButton(icon: "arrow.left") { router.pop() }
                TextField("", text: $query, prompt: Text("Search files").foregroundStyle(palette.secondaryText))
                    .focused($focused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty { IconButton(icon: "xmark") { query = "" } }
            }
            .foregroundStyle(palette.textColor)
            .background(Capsule().fill(palette.surface))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            if list.isEmpty {
                Placeholder(text: query.isEmpty ? "" : "No items found")
            } else {
                ThumbGrid(items: list, columns: columns, list: isList, horizontal: config.scrollHorizontally, spacing: CGFloat(config.thumbnailSpacing)) { m in
                    MediumCell(medium: m, list: isList, selected: false)
                        .onTapGesture {
                            if m.isVideo && config.gestureVideoPlayer {
                                router.push(.videoPlayer(m.id))
                            } else {
                                router.push(.viewer(path: "", id: m.id, only: list.map(\.id), slideshow: false))
                            }
                        }
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .task(id: store.version) { all = await store.media(in: "") }
        .onAppear { focused = true }
    }
}

/// ExcludedFoldersActivity (ManageFoldersAdapter): excluded albums, tap to remove.
struct ExcludedFoldersView: View {
    @Environment(MediaStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @State private var add = false

    var body: some View {
        let excluded = store.allAlbums.filter { config.excludedFolders.contains($0.path) }
        VStack(spacing: 0) {
            TopBar(title: "Excluded folders", onBack: nil, background: nil, tint: nil) {
                IconButton(icon: "plus") { add = true }
            }
            if excluded.isEmpty {
                Placeholder(text: "Excluding folders will make them hidden just in Fossify Gallery, they will still be visible in other applications.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(excluded) { d in
                            HStack {
                                Text(d.name).font(.system(size: 16))
                                Spacer()
                                IconButton(icon: "xmark") {
                                    config.excludedFolders.remove(d.path)
                                    store.reload()
                                }
                            }
                            .padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .sheet(isPresented: $add) {
            DialogFrame(title: "Exclude") {
                ForEach(store.allAlbums.filter { !config.excludedFolders.contains($0.path) }) { d in
                    Button {
                        config.excludedFolders.insert(d.path)
                        store.reload()
                        add = false
                    } label: {
                        Text(d.name).foregroundStyle(palette.textColor).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
