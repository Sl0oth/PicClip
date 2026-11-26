import AppKit
import UniformTypeIdentifiers

enum ImageActions {
    /// Puts the image data *and* the file on the pasteboard in one item:
    /// image editors/chat apps take the image, Finder takes the file.
    static func copy(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { NSSound.beep(); return }
        let type = UTType(filenameExtension: url.pathExtension) ?? .png
        let item = NSPasteboardItem()
        item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        item.setString(url.absoluteString, forType: .fileURL)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openInPreview(_ url: URL) {
        guard let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
            NSWorkspace.shared.open(url); return
        }
        NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
    }

    static func trash(_ url: URL) {
        NSWorkspace.shared.recycle([url])
    }
}
