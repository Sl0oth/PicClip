// Hides (or with "show", un-hides) every regular app except PicClip, via the Accessibility API.
// Usage: hideall [show] [keep-textedit]
import AppKit
import ApplicationServices
let args = CommandLine.arguments
let hide = !args.contains("show")
let keep = Set(["app.picclip.PicClip"] + (args.contains("keep-textedit") ? ["com.apple.TextEdit"] : []))
for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !keep.contains(app.bundleIdentifier ?? "") {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    let result = AXUIElementSetAttributeValue(element, kAXHiddenAttribute as CFString, (hide ? kCFBooleanTrue : kCFBooleanFalse)!)
    if result != .success { print("couldn't \(hide ? "hide" : "show") \(app.localizedName ?? "?"): \(result.rawValue)") }
}
