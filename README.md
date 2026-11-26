# PicClip

A tiny macOS menu bar app that replaces the screenshot thumbnail that vanishes after a few seconds with one that **stays put** until you're done with it.

Take a screenshot (⇧⌘3 / ⇧⌘4) and a preview clips itself to the corner of your screen:

- **Drag** it into any app to drop the image in
- **Copy** it, **pin** it above all your windows, or **✕** dismiss it
- **Click** it to open the library, where you can mark it up with a marker, black out, blur, or pixelate parts of it

Quitting PicClip gives you back the normal macOS thumbnail.

## Requirements
macOS 15 or later.

## Build & run
```sh
./build.sh run
```
That builds `build/PicClip.app` and launches it. Drag it into `/Applications` to keep it, and turn on **Launch at Login** from the menu bar icon.

## Update
```sh
git pull && ./build.sh run
```

## Project layout
| Path | What |
| --- | --- |
| `Sources/PicClip/` | The app (Swift, AppKit + SwiftUI) |
| `Resources/Info.plist` | Bundle settings |
| `Resources/Icon/` | Icon sources (`AppIcon.svg`, `MenuBarIcon.svg`); run `make-icon.sh` after editing |
| `build.sh` | Builds and signs the `.app` |
