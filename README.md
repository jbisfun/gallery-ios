# gallery-ios

[Fossify Gallery](https://github.com/FossifyOrg/Gallery) re-created for iOS in SwiftUI, on top of the system photo library (PhotoKit): folders are albums, files are photos and videos.

    idl build -c release     # -> build/release/FossifyGallery.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyGallery

Ported: folders screen (grid/list, square or rounded thumbnails, media count styles, pinning, custom drag order, cover images, sorting, media type filter, column count with pinch zoom, horizontal scrolling, search, show all folders content, default folder, temporarily show hidden/excluded); folder actions (rename, hide, exclude, lock, copy/move content, delete, properties); media screen with sorting, grouping, view types and file name toggle; multi-select actions (share, rotate, favorite, hide, copy/move, resize, fix date taken, edit, delete, properties); fullscreen viewer with deep zoom, 1:1 zoom, rotating gestures, instant change, down gesture, brightness gestures, extended details, bottom actions, slideshow, print, show on map, change orientation; video player with seek bar, ±10 s, playback speed, mute, loop, autoplay, remembered position, volume/brightness gestures and the separate-screen player; editor with crop (free, 1:1, 4:3, 16:9, other ratios), rotate, flip, filters and drawing, saved as a copy or over the original; file search; open camera; the folder home-screen widget (folder thumbnail with optional name, background color and transparency, text color); excluded folders; password protection of the app, hidden items, excluded folders, deletion and folders; date format and every applicable setting.

Differences forced by iOS: deleted media go to the system's Recently Deleted (after iOS' own confirmation), so there is no in-app recycle bin; "Hide" uses the Photos Hidden album instead of .nomedia files, so there are no managed hidden or included folders and no subfolder grouping; files can't be renamed or set as wallpaper; the home-screen widget is available inside launcher-ios (iOS home-screen widgets would need a WidgetKit extension); no launcher shortcuts, pick/view intents for other apps, default player choice, notch setting, in-app language switch or settings/favorites export; filters are Core Image photo effects and the volume gesture changes the player volume.

GPL-3.0, like the original.
