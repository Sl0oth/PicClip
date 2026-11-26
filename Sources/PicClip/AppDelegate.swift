import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ScreenshotStore()
    private let previews = PreviewManager()
    private let pins = PinManager()
    private lazy var library = LibraryController(store: store)
    private let updater = Updater()
    private var statusItem: NSStatusItem?
    private var previewsMenuItem: NSMenuItem?
    private var loginMenuItem: NSMenuItem?

    private var previewsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "previewsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "previewsEnabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMover.offerMoveIfNeeded() { return }
        if previewsEnabled { SystemScreenshots.suppressThumbnail() }
        CrashGuard.install(restoring: SystemScreenshots.savedThumbnail ?? true)

        previews.onOpen = { [unowned self] in library.show(selecting: $0) }
        previews.onPin = { [unowned self] in pins.pin($0, from: $1) }
        pins.onOpen = { [unowned self] in library.show(selecting: $0) }
        library.onPin = { [unowned self] in pins.pin($0) }
        store.onNewScreenshot = { [unowned self] in if previewsEnabled { previews.show($0) } }
        store.onFolderAccessDenied = { [unowned self] in askForFolderAccess() }
        store.start()

        NSApp.mainMenu = makeMainMenu()
        makeStatusItem()
        updater?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SystemScreenshots.restoreThumbnail()
    }

    /// Opening the app again from Finder/Spotlight shows the library.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        library.show()
        return false
    }

    /// One-time nudge, opened straight to the switch they need to flip.
    private func askForFolderAccess() {
        let alert = NSAlert()
        alert.messageText = "PicClip needs to see your screenshots"
        alert.informativeText = """
            macOS is blocking PicClip from your \(SystemScreenshots.folder.lastPathComponent) folder, where screenshots are saved.

            In Files & Folders, find PicClip and turn on “\(SystemScreenshots.folder.lastPathComponent) Folder”. You only do this once — PicClip picks it up right away.
            """
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Status menu

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem("Open Library", #selector(openLibrary), key: "l"))
        menu.addItem(menuItem("Open Screenshots Folder", #selector(openFolder)))
        menu.addItem(.separator())
        let previewsItem = menuItem("Floating Previews", #selector(togglePreviews))
        let loginItem = menuItem("Launch at Login", #selector(toggleLogin))
        menu.addItem(previewsItem)
        menu.addItem(loginItem)
        menu.addItem(menuItem("Check for Updates…", #selector(checkForUpdates)))
        previewsMenuItem = previewsItem
        loginMenuItem = loginItem
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PicClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// The clip-and-photo template glyph (tinted by macOS for light/dark), SF Symbol fallback.
    private static var menuBarIcon: NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "PicClip")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "PicClip"
        return image
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        previewsMenuItem?.state = previewsEnabled ? .on : .off
        loginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openLibrary() { library.show() }

    @objc private func checkForUpdates() { updater?.check(userInitiated: true) }

    @objc private func openFolder() { NSWorkspace.shared.open(SystemScreenshots.folder) }

    @objc private func togglePreviews() {
        previewsEnabled.toggle()
        // Off = hand screenshots back to the native macOS thumbnail.
        if previewsEnabled { SystemScreenshots.suppressThumbnail() } else { SystemScreenshots.restoreThumbnail() }
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: Main menu (visible only while the library window is open)

    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About PicClip", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(menuItem("Check for Updates…", #selector(checkForUpdates)))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide PicClip", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit PicClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = windowMenu

        let main = NSMenu()
        for submenu in [appMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }
}
