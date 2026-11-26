import Foundation
import Observation
import UniformTypeIdentifiers

struct Screenshot: Identifiable, Hashable {
    let url: URL
    let date: Date
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// Every screenshot on disk, plus a callback for fresh captures.
/// - Folder watcher on the screenshot folder: instant detection (checks the xattr macOS stamps on screenshots).
/// - Spotlight query: finds screenshots anywhere in ~ for the library, and backs up the watcher.
@MainActor @Observable
final class ScreenshotStore {
    private(set) var shots: [Screenshot] = []
    /// Bumped when PicClip edits a file, so thumbnails showing it reload.
    private(set) var revisions: [URL: Int] = [:]
    @ObservationIgnored var onNewScreenshot: (Screenshot) -> Void = { _ in }
    @ObservationIgnored private let query = NSMetadataQuery()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var spotlightShots: [Screenshot] = []
    @ObservationIgnored private var folderShots: [URL: Screenshot] = [:]
    @ObservationIgnored private var folderNames: Set<String> = []
    @ObservationIgnored private var announced: Set<URL> = []
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private let folder = SystemScreenshots.folder

    func didEdit(_ url: URL) { revisions[url, default: 0] += 1 }

    func start() {
        watchFolder()
        startQuery()
    }

    // MARK: Folder watcher

    private func watchFolder() {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        folderNames = Set(listFolder())
        for name in folderNames { if let shot = screenshot(named: name) { folderShots[shot.url] = shot } }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scanFolder() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
        publish()
    }

    private func scanFolder(retry: Int = 0) {
        let names = Set(listFolder())
        let added = names.subtracting(folderNames)
        let removed = folderNames.subtracting(names)
        folderNames = names
        removed.forEach { folderShots[folder.appending(path: $0)] = nil }

        var pending = false
        for name in added {
            if let shot = screenshot(named: name) {
                folderShots[shot.url] = shot
                announce(shot)
            } else if retry < 3, isImage(name) {
                folderNames.remove(name) // screencapture may stamp the xattr just after the file lands; look again
                pending = true
            }
        }
        if pending {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.scanFolder(retry: retry + 1) }
        }
        if !added.isEmpty || !removed.isEmpty { publish() }
    }

    private func listFolder() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private func isImage(_ name: String) -> Bool {
        UTType(filenameExtension: (name as NSString).pathExtension)?.conforms(to: .image) ?? false
    }

    private func screenshot(named name: String) -> Screenshot? {
        guard !name.hasPrefix("."), isImage(name) else { return nil }
        let url = folder.appending(path: name)
        guard getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0 else { return nil }
        let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
        return Screenshot(url: url, date: date)
    }

    // MARK: Spotlight

    private func startQuery() {
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemContentTypeTree == 'public.image'")
        var scopes: [Any] = [NSMetadataQueryUserHomeScope]
        if !folder.path.hasPrefix(NSHomeDirectory()) { scopes.append(folder) }
        query.searchScopes = scopes
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]
        query.notificationBatchingInterval = 0.1

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reloadQuery() }
            },
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
                let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reloadQuery()
                    added.compactMap(Self.screenshot).forEach(self.announce)
                }
            },
        ]
        query.start()
    }

    private func reloadQuery() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        spotlightShots = (query.results as? [NSMetadataItem] ?? []).compactMap(Self.screenshot)
        publish()
    }

    private static func screenshot(_ item: NSMetadataItem) -> Screenshot? {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
              !path.contains("/.Trash/") else { return nil }
        let date = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? .distantPast
        return Screenshot(url: URL(fileURLWithPath: path), date: date)
    }

    // MARK: Merge

    private func announce(_ shot: Screenshot) {
        // Only brand-new captures (not old files moved/restored), and only once per file.
        guard shot.date > Date().addingTimeInterval(-30), announced.insert(shot.url).inserted else { return }
        onNewScreenshot(shot)
    }

    private func publish() {
        let spotlightURLs = Set(spotlightShots.map(\.url))
        let extras = folderShots.values.filter { !spotlightURLs.contains($0.url) }
        let live = spotlightShots.filter { folderShots[$0.url] != nil || $0.url.deletingLastPathComponent() != folder }
        shots = (extras + live).sorted { $0.date > $1.date }
    }
}
