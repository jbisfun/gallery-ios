import FossifyCommons
import GalleryKit
import SwiftUI

struct GalleryApp: App {
    @UIApplicationDelegateAdaptor(OrientationLockDelegate.self) private var orientation

    var body: some Scene {
        WindowGroup { GalleryRoot() }
    }
}

GalleryApp.main()
