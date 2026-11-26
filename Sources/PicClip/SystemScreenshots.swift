import Foundation

/// Reads/writes the system screenshot preferences (`com.apple.screencapture`).
enum SystemScreenshots {
    private static let domain = "com.apple.screencapture" as CFString
    private static let thumbnailKey = "show-thumbnail" as CFString
    private static let savedKey = "savedNativeThumbnail"

    /// Where macOS saves screenshots (defaults to ~/Desktop).
    static var folder: URL {
        if let path = CFPreferencesCopyAppValue("location" as CFString, domain) as? String, !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private static var nativeThumbnail: Bool {
        get {
            CFPreferencesAppSynchronize(domain)
            return CFPreferencesCopyAppValue(thumbnailKey, domain) as? Bool ?? true
        }
        set {
            CFPreferencesSetAppValue(thumbnailKey, NSNumber(value: newValue), domain)
            CFPreferencesAppSynchronize(domain)
        }
    }

    /// The user's own setting from before PicClip changed it (nil = PicClip hasn't changed it).
    static var savedThumbnail: Bool? { UserDefaults.standard.object(forKey: savedKey) as? Bool }

    /// Turns the native thumbnail off, remembering the user's original setting (survives crashes).
    static func suppressThumbnail() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: savedKey) == nil { defaults.set(nativeThumbnail, forKey: savedKey) }
        nativeThumbnail = false
    }

    /// Puts the native thumbnail setting back to what it was before PicClip touched it.
    static func restoreThumbnail() {
        let defaults = UserDefaults.standard
        guard let saved = defaults.object(forKey: savedKey) as? Bool else { return }
        nativeThumbnail = saved
        defaults.removeObject(forKey: savedKey)
    }
}
