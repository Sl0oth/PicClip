import AppKit

/// Opened from Downloads or a disk image? macOS runs it from a hidden read-only copy ("App Translocation"),
/// where it can't update itself. Offer the usual one-click move to /Applications.
@MainActor
enum AppMover {
    /// Returns true if PicClip is moving itself (this copy is about to quit).
    static func offerMoveIfNeeded() -> Bool {
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let path = bundle.path
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path
        guard path.contains("/AppTranslocation/") || path.hasPrefix(downloads + "/") || path.hasPrefix("/Volumes/")
        else { return false } // already installed, or a dev build — leave it alone

        let alert = NSAlert()
        alert.messageText = "Move PicClip to Applications?"
        alert.informativeText = "PicClip can only keep itself up to date from your Applications folder. You can delete the copy in Downloads afterwards."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let destination = URL(fileURLWithPath: "/Applications/PicClip.app")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: bundle, to: destination)
            // The copy keeps the "downloaded" flag; we put it there ourselves, so clear it.
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
            try? xattr.run()
            xattr.waitUntilExit()
        } catch {
            let failed = NSAlert(error: error)
            failed.informativeText = "Drag PicClip into Applications yourself. (\(error.localizedDescription))"
            failed.runModal()
            return false
        }
        Updater.relaunch(destination)
        return true
    }
}
