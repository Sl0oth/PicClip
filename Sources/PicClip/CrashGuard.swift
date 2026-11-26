import Darwin

/// If PicClip ever crashes, put the native screenshot thumbnail back so the user isn't left with *no* preview.
/// argv is built up front so the handler allocates nothing; it spawns `defaults` (posix_spawn is a single syscall on Darwin), then re-raises so the crash report is still written.
enum CrashGuard {
    nonisolated(unsafe) fileprivate static var argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?

    static func install(restoring thumbnail: Bool) {
        let args = ["/usr/bin/defaults", "write", "com.apple.screencapture", "show-thumbnail", "-bool", thumbnail ? "true" : "false"]
        let buffer = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: args.count + 1)
        for (i, arg) in args.enumerated() { buffer[i] = strdup(arg) }
        buffer[args.count] = nil
        argv = buffer
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] { signal(sig, crashHandler) }
    }
}

private func crashHandler(_ sig: Int32) {
    if let argv = CrashGuard.argv {
        var pid: pid_t = 0
        posix_spawn(&pid, argv[0]!, nil, nil, argv, nil)
    }
    signal(sig, SIG_DFL)
    raise(sig)
}
