import FossifyCommons
import Observation
import SwiftUI
import UIKit

enum Route: Hashable {
    /// MediaActivity: one folder, "" = all folders.
    case media(String)
    /// ViewPagerActivity on a medium of a folder ("" = all folders); `only` limits it to a set (search results).
    case viewer(path: String, id: String, only: [String]?, slideshow: Bool)
    /// VideoPlayerActivity ("Play videos on a separate screen").
    case videoPlayer(String)
    case editor(String)
    case search
    case settings
    case customizeColors
    case excludedFolders
    case about
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []

    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
}

/// The whole app as one view: the standalone app's window content, and what
/// the launcher presents.
public struct GalleryRoot: View {
    @State private var store = MediaStore()
    @State private var router = Router()

    public init() {}

    public var body: some View {
        RootView()
            .environment(store)
            .environment(router)
            .environment(Config.shared)
            .appLock()
            .fossifyTheme()
    }
}

struct RootView: View {
    @Environment(MediaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.scenePhase) private var phase
    @State private var openedDefault = false

    var body: some View {
        @Bindable var router = router
        @Bindable var store = store
        NavigationStack(path: $router.path) {
            Group {
                switch store.access {
                case .granted, .limited:
                    if config.showAll { MediaView(path: "") } else { MainView() }
                case .denied: PermissionDenied()
                case .unknown: Color.clear.paletteBackground()
                }
            }
            .navigationDestination(for: Route.self) { route in
                Group {
                    switch route {
                    case .media(let path): MediaView(path: path)
                    case .viewer(let path, let id, let only, let slideshow): ViewerView(path: path, startID: id, only: only, startSlideshow: slideshow)
                    case .videoPlayer(let id): SeparateVideoPlayer(id: id)
                    case .editor(let id): EditorView(id: id)
                    case .search: SearchView()
                    case .settings: SettingsView()
                    case .customizeColors: CustomizeColorsView()
                    case .excludedFolders: ExcludedFoldersView()
                    case .about: AboutView(app: .gallery)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .paletteBackground()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .toast($store.toast)
        .onAppear { store.requestAccess() }
        .onChange(of: phase) { _, p in
            if p == .active { store.requestAccess() }
            // Temporarily shown hidden items stop showing when the app is left (SHOW_TEMP_HIDDEN_DURATION).
            if p == .background && config.temporarilyShowHidden {
                config.temporarilyShowHidden = false
                store.reload()
            }
        }
        .onChange(of: store.loadedInitial) { _, loaded in if loaded { openDefaultFolder() } }
    }

    /// openDefaultFolder().
    private func openDefaultFolder() {
        guard !openedDefault else { return }
        openedDefault = true
        let folder = config.defaultFolder
        guard !folder.isEmpty, router.path.isEmpty else { return }
        if store.allAlbums.contains(where: { $0.path == folder }) {
            router.push(.media(folder))
        } else {
            config.defaultFolder = ""
        }
    }
}

struct PermissionDenied: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 16) {
            Text("Fossify Gallery needs full access to display all your photos and videos.")
                .font(.system(size: 17).italic())
                .multilineTextAlignment(.center)
            Button {
                Launcher.open(URL(string: UIApplication.openSettingsURLString))
            } label: {
                Text("Open settings").underline().foregroundStyle(palette.primaryColor)
            }
            CloseAppButton()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.backgroundColor.ignoresSafeArea())
    }
}
