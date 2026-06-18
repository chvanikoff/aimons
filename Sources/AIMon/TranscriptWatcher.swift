import Foundation
import AIMonCore

/// Polls ~/.claude/projects for live Claude Code session transcripts and reports
/// session start/end. Polling (not FSEvents) is intentional for v1: simple and robust.
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

    private var tracked: Set<String> = []
    private var urlBySession: [String: URL] = [:]
    private var timer: Timer?

    init(projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
         pollInterval: TimeInterval = 2,
         liveWindow: TimeInterval = 30,
         staleTimeout: TimeInterval = 90) {
        self.projectsRoot = projectsRoot
        self.pollInterval = pollInterval
        self.liveWindow = liveWindow
        self.staleTimeout = staleTimeout
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
        let decision = WatcherReconciler.reconcile(
            files: files, tracked: tracked, now: Date(),
            liveWindow: liveWindow, staleTimeout: staleTimeout)

        for id in decision.toStart {
            guard let url = urlBySession[id], let cwd = cwdFromFile(url) else { continue }
            tracked.insert(id)
            let seed = ProjectIdentity.seed(forCWD: cwd)
            onStarted?(StartedSession(sessionId: id, cwd: cwd, projectSeed: seed))
        }
        for id in decision.toEnd {
            tracked.remove(id)
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
}
