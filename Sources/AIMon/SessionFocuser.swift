import AppKit
import AIMonCore

/// On click, brings the terminal app that launched a project's session to the front.
///
/// The exact tab/pane isn't reliably addressable (sessions often run inside tmux, and terminals
/// vary), so we focus the *app* — identified by the session process's `__CFBundleIdentifier`
/// env var (e.g. iTerm2, Terminal, Ghostty). All process I/O is off-main; activation is on main.
final class SessionFocuser {
    private let queue = DispatchQueue(label: "io.romanc.aimon.focus", qos: .userInitiated)
    private let probeTimeout: TimeInterval = 2

    func focus(projectCWD cwd: String) {
        queue.async { [weak self] in
            guard let self, let pid = self.claudePID(forCWD: cwd),
                  let bundleID = self.bundleIdentifier(ofPID: pid) else {
                Log.lifecycle.notice("focus: no terminal resolved for \(cwd)")
                return
            }
            DispatchQueue.main.async {
                // NSWorkspace.openApplication(activates:true) reliably brings a running app forward
                // even from a background/accessory agent — unlike NSRunningApplication.activate,
                // which modern macOS denies as focus-stealing when the caller isn't frontmost.
                let ws = NSWorkspace.shared
                if let url = ws.urlForApplication(withBundleIdentifier: bundleID) {
                    let cfg = NSWorkspace.OpenConfiguration()
                    cfg.activates = true
                    ws.openApplication(at: url, configuration: cfg) { _, error in
                        if let error { Log.lifecycle.error("focus open failed: \(error.localizedDescription)") }
                    }
                } else {
                    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                        .first?.activate(options: [.activateAllWindows])
                }
                Log.lifecycle.notice("focus terminal \(bundleID) for \(cwd)")
            }
        }
    }

    /// A live `claude` pid whose cwd matches (any; "most recent" isn't distinguishable here).
    private func claudePID(forCWD cwd: String) -> Int32? {
        guard let ps = run("/bin/ps", ["-axww", "-o", "pid=", "-o", "command="]) else { return nil }
        let pids = ProcessScan.claudePIDs(fromPS: ps)
        guard !pids.isEmpty,
              let lsof = run("/usr/sbin/lsof", ["-a", "-p", pids.joined(separator: ","), "-d", "cwd", "-Fpn"])
        else { return nil }
        var current: Int32?
        for line in lsof.split(separator: "\n") {
            if line.hasPrefix("p") {
                current = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = current,
                      PathNormalizer.standardize(String(line.dropFirst())) == cwd {
                return pid
            }
        }
        return nil
    }

    private func bundleIdentifier(ofPID pid: Int32) -> String? {
        guard let out = run("/bin/ps", ["eww", "-p", "\(pid)"]) else { return nil }
        for token in out.split(whereSeparator: { $0 == " " || $0 == "\n" })
        where token.hasPrefix("__CFBundleIdentifier=") {
            return String(token.dropFirst("__CFBundleIdentifier=".count))
        }
        return nil
    }

    private func run(_ launchPath: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        if done.wait(timeout: .now() + probeTimeout) == .timedOut { process.terminate(); return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
