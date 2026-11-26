import AppKit
import Security

/// Self-updates from GitHub Releases. No Sparkle, no paid signing:
/// files this app downloads aren't quarantined, so the swapped-in update never trips Gatekeeper.
@MainActor
final class Updater {
    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let assets: [Asset]

        var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
        var zip: URL? { assets.first { $0.name == Updater.assetName }?.browser_download_url }
    }

    enum UpdateError: LocalizedError {
        case badResponse(Int), noApp, wrongApp, badSignature, tool(String)
        var errorDescription: String? {
            switch self {
            case .badResponse(404): "No published release found on GitHub."
            case .badResponse(let code): "GitHub answered with HTTP \(code)."
            case .noApp: "The download didn't contain PicClip.app."
            case .wrongApp: "The download isn't PicClip."
            case .badSignature: "The download's signature doesn't check out, so it wasn't installed."
            case .tool(let name): "\(name) failed while installing the update."
            }
        }
    }

    nonisolated static let assetName = "PicClip.zip"
    nonisolated static let installMarker = "<!-- install -->" // keep in sync with release.sh
    private let repo: String
    private let currentVersion: String
    private var isBusy = false
    private var timer: Timer?
    private let skippedKey = "skippedUpdateVersion"

    init?(bundle: Bundle = .main) {
        guard let repo = bundle.object(forInfoDictionaryKey: "PicClipGitHubRepo") as? String, !repo.isEmpty,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        self.repo = repo
        self.currentVersion = version
    }

    /// Quiet check shortly after launch, then once a day.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.check(userInitiated: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(userInitiated: false) }
        }
    }

    func check(userInitiated: Bool) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let release = try await Self.fetchLatest(from: feedURL)
                guard Self.isVersion(release.version, newerThan: currentVersion) else {
                    if userInitiated { alert("You're up to date", "PicClip \(currentVersion) is the latest version.") }
                    return
                }
                if !userInitiated, UserDefaults.standard.string(forKey: skippedKey) == release.version { return }
                try await offer(release)
            } catch {
                if userInitiated { alert("Couldn't check for updates", error.localizedDescription) }
            }
        }
    }

    // MARK: Flow

    private func offer(_ release: Release) async throws {
        let prompt = NSAlert()
        prompt.messageText = "PicClip \(release.version) is available"
        // Release notes end with first-install help for new users; existing users don't need it.
        let changes = release.body?.components(separatedBy: Updater.installMarker).first ?? ""
        let notes = changes.trimmingCharacters(in: .whitespacesAndNewlines)
        prompt.informativeText = "You have \(currentVersion).\(notes.isEmpty ? "" : "\n\n" + String(notes.prefix(600)))"
        prompt.addButton(withTitle: "Install & Relaunch")
        prompt.addButton(withTitle: "Later")
        prompt.addButton(withTitle: "Skip This Version")
        NSApp.activate()
        switch prompt.runModal() {
        case .alertFirstButtonReturn:
            guard let zip = release.zip else { NSWorkspace.shared.open(release.html_url); return }
            try await install(from: zip)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: skippedKey)
        default:
            break
        }
    }

    private func install(from zip: URL) async throws {
        let target = Bundle.main.bundleURL
        var request = URLRequest(url: zip)
        request.setValue("PicClip-Updater", forHTTPHeaderField: "User-Agent")
        let (download, response) = try await URLSession.shared.download(for: request)
        try Self.ensureOK(response)
        let newApp = try await Task.detached { try Self.unpack(download, near: target) }.value
        do {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
        } catch {
            // No write access where the app lives (e.g. a standard user in /Applications): hand it over manually.
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appending(path: "PicClip.app")
            try? FileManager.default.removeItem(at: downloads)
            try FileManager.default.moveItem(at: newApp, to: downloads)
            NSWorkspace.shared.activateFileViewerSelecting([downloads])
            alert("Almost done", "PicClip couldn't replace itself (\(error.localizedDescription)). Drag the new PicClip from Downloads into Applications.")
            return
        }
        Self.relaunch(target)
    }

    /// Quits, and once this process is fully gone (so only one copy ever touches the screenshot prefs), opens `app`.
    static func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", app.path]
        try? shell.run()
        NSApp.terminate(nil)
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }

    // MARK: Pure helpers (no UI — unit-testable)

    /// GitHub's "latest release" endpoint. For testing an update without publishing one:
    /// `defaults write app.picclip.PicClip UpdateFeedURL file:///path/to/feed.json` (same JSON shape as GitHub's).
    private var feedURL: URL {
        if let override = UserDefaults.standard.string(forKey: "UpdateFeedURL"), let url = URL(string: override) { return url }
        return URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }

    nonisolated static func fetchLatest(from url: URL, session: URLSession = .shared) async throws -> Release {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PicClip-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try ensureOK(response)
        return try JSONDecoder().decode(Release.self, from: data)
    }

    nonisolated static func ensureOK(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.badResponse(http.statusCode)
        }
    }

    /// "1.10.0" > "1.9.2"; missing parts count as 0.
    nonisolated static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let parse = { (s: String) in s.split(separator: ".").map { Int($0) ?? 0 } }
        let x = parse(a), y = parse(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Unzips next to `target` (same volume, so the swap is a rename) and vets the result.
    nonisolated static func unpack(_ zip: URL, near target: URL) throws -> URL {
        let fm = FileManager.default
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        guard let app = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" })
        else { throw UpdateError.noApp }
        guard let id = Bundle(url: app)?.bundleIdentifier, id == Bundle(url: target)?.bundleIdentifier else { throw UpdateError.wrongApp }
        try verifySignature(of: app, against: target)
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path]) // belt and braces
        return app
    }

    /// The update's signature must be intact. If the installed app has a real (non-ad-hoc) signer,
    /// the update must satisfy the installed app's designated requirement — i.e. come from the same certificate.
    nonisolated static func verifySignature(of app: URL, against installed: URL) throws {
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess, let newCode,
              SecStaticCodeCheckValidity(newCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
        else { throw UpdateError.badSignature }

        var oldCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecStaticCodeCreateWithPath(installed as CFURL, [], &oldCode) == errSecSuccess, let oldCode,
              SecCodeCopyDesignatedRequirement(oldCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return } // unsigned dev build
        if (text as String).contains("cdhash") { return } // ad-hoc: no stable signer to compare against
        guard SecStaticCodeCheckValidity(newCode, [], requirement) == errSecSuccess else { throw UpdateError.badSignature }
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.tool((tool as NSString).lastPathComponent) }
    }
}
