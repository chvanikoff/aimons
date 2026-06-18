import Foundation
import AIMonCore

/// Polls ~/.claude/projects for live Claude Code session transcripts and reports
/// session start/end. Polling (not FSEvents) is intentional for v1: simple and robust.
///
/// Spawning is driven by transcript mtime; ending is driven by whether a live
/// `claude` CLI process still backs the session's project — so an idle session
/// doesn't falsely despawn, and Ctrl-C despawns within one poll instead of after
/// a long stale timeout.
final class TranscriptWatcher {
    struct StartedSession {
        let sessionId: String
        let cwd: String
        let projectSeed: UInt64
    }

    var onStarted: ((StartedSession) -> Void)?
    var onEnded: ((String) -> Void)?

    private let projectsRoot: URL
    private let pollInterval: TimeInterval
    private let liveWindow: TimeInterval
    private let staleTimeout: TimeInterval
    /// Returns the cwds of live `claude` CLI processes, or nil if the probe is
    /// unavailable (so the reconciler falls back to the mtime timeout). Injectable for tests.
    private let liveCWDsProvider: () -> [String]?

    private var tracked: [String: String] = [:]   // sessionId -> standardized cwd
    private var urlBySession: [String: URL] = [:]
    private var timer: Timer?

    init(projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
         pollInterval: TimeInterval = 2,
         liveWindow: TimeInterval = 30,
         staleTimeout: TimeInterval = 90,
         liveCWDsProvider: @escaping () -> [String]? = TranscriptWatcher.scanLiveClaudeCWDs) {
        self.projectsRoot = projectsRoot
        self.pollInterval = pollInterval
        self.liveWindow = liveWindow
        self.staleTimeout = staleTimeout
        self.liveCWDsProvider = liveCWDsProvider
    }

    func start() {
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)   // keep ticking during menu tracking / drags
        self.timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let files = scanFiles()
        let counts = liveCWDsProvider().map { ProcessScan.counts(of: $0.map(Self.standardize)) }
        let trackedSessions = tracked.map { TrackedSession(sessionId: $0.key, cwd: $0.value) }

        let decision = WatcherReconciler.reconcile(
            files: files, tracked: trackedSessions, liveCWDCounts: counts,
            now: Date(), liveWindow: liveWindow, staleTimeout: staleTimeout)

        for id in decision.toStart {
            guard let url = urlBySession[id], let rawCwd = cwdFromFile(url) else { continue }
            let cwd = Self.standardize(rawCwd)
            let trackedAtCwd = tracked.values.filter { $0 == cwd }.count
            guard WatcherReconciler.canSpawn(cwd: cwd, trackedAtCwd: trackedAtCwd, liveCWDCounts: counts)
            else { continue }   // directory already has as many monsters as live processes
            tracked[id] = cwd
            onStarted?(StartedSession(sessionId: id, cwd: cwd, projectSeed: ProjectIdentity.seed(forCWD: cwd)))
        }
        for id in decision.toEnd {
            tracked[id] = nil
            onEnded?(id)
        }
    }

    /// Enumerate ~/.claude/projects/*/*.jsonl, recording each session's mtime and URL.
    private func scanFiles() -> [TranscriptFile] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var result: [TranscriptFile] = []
        var urls: [String: URL] = [:]
        for dir in projectDirs {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for url in entries where url.pathExtension == "jsonl" {
                let sessionId = url.deletingPathExtension().lastPathComponent
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date.distantPast
                result.append(TranscriptFile(sessionId: sessionId, lastModified: mtime))
                urls[sessionId] = url
            }
        }
        urlBySession = urls
        return result
    }

    /// Read the first 64 KB of a transcript and return the first cwd found.
    private func cwdFromFile(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = handle.readData(ofLength: 64 * 1024)
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            if let meta = TranscriptDecoder.meta(fromLine: String(line)), let cwd = meta.cwd {
                return cwd
            }
        }
        return nil
    }

    // MARK: - Process probe (impure; parsing lives in AIMonCore.ProcessScan)

    private static func standardize(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// cwds of every live `claude` CLI process, via `ps` (to match argv, since the
    /// process *name* is the version string) then `lsof` (for each pid's cwd).
    /// Returns nil only if the probe itself can't run, so liveness degrades to mtime.
    static func scanLiveClaudeCWDs() -> [String]? {
        guard let psOut = run("/bin/ps", ["-axww", "-o", "pid=", "-o", "command="]) else { return nil }
        let pids = ProcessScan.claudePIDs(fromPS: psOut)
        if pids.isEmpty { return [] }   // no claude CLI running — a legitimate empty result
        guard let lsofOut = run("/usr/sbin/lsof",
                                ["-a", "-p", pids.joined(separator: ","), "-d", "cwd", "-Fn"]) else { return nil }
        return ProcessScan.cwds(fromLSOF: lsofOut)
    }

    private static func run(_ launchPath: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
