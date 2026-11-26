# PicClip — Plan (v1)

Menu bar app (no Dock icon) that replaces the macOS screenshot thumbnail with a persistent one.

## Features (v1 scope — nothing else)
1. Disable native floating thumbnail (`com.apple.screencapture show-thumbnail = false`), restore original value on quit / toggle off.
2. Detect new screenshots: folder watcher on the screenshot folder (instant, checks the `kMDItemIsScreenCapture` xattr) + `NSMetadataQuery` backup that also feeds the library with screenshots anywhere in ~.
3. Floating preview, bottom-right of the screen under the mouse, slides in, **stays** until dismissed. Stacks up to 4.
   - Drag out → drops the file into any app (preview disappears on successful drop)
   - Hover → X (dismiss), Copy, Pin buttons
   - Click → opens Library window with that screenshot selected
4. Pin → always-on-top resizable window of the image (drag to move, X to close, double-click opens library).
5. Library window: thumbnail grid + large detail; Copy, Pin, Share, Show in Finder, Open in Preview, Move to Trash. Drag out of grid/detail.
6. Status menu: Open Library, Open Screenshots Folder, Floating Previews toggle, Launch at Login, Quit.

## Architecture (Sources/PicClip)
- `main.swift` – AppKit entry
- `AppDelegate.swift` – wiring, status menu, main menu
- `SystemScreenshots.swift` – screencapture prefs (thumbnail, folder)
- `ScreenshotStore.swift` – folder watcher + NSMetadataQuery → `[Screenshot]` + new-shot callback
- `Thumbnails.swift` – CGImageSource downsampling + NSCache
- `ImageActions.swift` – copy / reveal / open / trash
- `FloatingCard.swift` – shared SwiftUI card + AppKit mouse/drag surface + panel (used by preview AND pin)
- `PreviewManager.swift` – preview stacking & animation
- `PinManager.swift` – pinned windows
- `Library.swift` – library window controller + SwiftUI views

## Build / verify
`./build.sh` → `build/PicClip.app` (SwiftPM + hand-assembled bundle, ad-hoc signed). `./build.sh run` builds & launches.

## v1.1 — Editor + library refresh
- Editor in the library's detail pane, floating tool palette (Liquid Glass on macOS 26+, material below):
  Select (V), Marker (M, 6 colors, 3 sizes), Black Out (R), Blur (B), Pixelate (P), Undo ⌘Z / Redo ⇧⌘Z, Revert, Save ⌘S.
- Edits are non-destructive in memory (`[Annotation]` in image-pixel coords) until saved; saved in place (keeps screenshot xattr).
  Switching screenshot or Copy/Pin/Share auto-saves pending edits first (like native Markup's Done).
- One renderer (`AnnotationRenderer`, CGContext, y-down) draws both the live canvas and the full-res export.
  Blur/pixelate = pre-filtered copy of the image drawn clipped to each rect; strength scales with image size so live == export.
- Library: grid grouped by day with sticky headers (Today / Yesterday / date), hover states, time-only labels,
  Preview-style canvas backdrop, info bar (name · dimensions · size · date), tool hint text.
- Files: new `Editor.swift`; edits to `Library.swift`, `Thumbnails.swift` (pixel size, invalidate), `ScreenshotStore.swift` (revisions).
