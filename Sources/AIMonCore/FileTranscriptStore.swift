import Foundation

/// Injectable clock so time-dependent logic is deterministic in tests.
public protocol Clock {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Source of the transcripts the engine reconciles against.
public protocol TranscriptStore {
    /// All transcripts currently present, each with mtime and resolved (standardized) cwd.
    /// Returns `nil` when the projects-root enumeration *failed* — distinct from a successful
    /// empty scan (`[]`) — so the caller can skip the tick instead of mass-despawning on a
    /// transient filesystem hiccup.
    func scan() -> [TranscriptFile]?
}

/// Source of live-process liveness (the `ps`/`lsof` probe lives in the executable shell).
public protocol ProcessProbe {
    /// Standardized cwds of live `claude` processes (with multiplicity), or `nil` if unavailable.
    func liveCWDs() -> [String]?
}

/// `TranscriptStore` backed by `~/.claude/projects/<slug>/<session>.jsonl`. Resolves each
/// session's cwd once (line-by-line, symlink-standardized) and caches it, since a session's
/// cwd never changes. Single-threaded use only (the shell calls it on a serial queue).
public final class FileTranscriptStore: TranscriptStore {
    private let projectsRoot: URL
    private let config: WatcherConfig
    private var cwdCache: [String: String] = [:]

    public init(projectsRoot: URL, config: WatcherConfig = .default) {
        self.projectsRoot = projectsRoot
        self.config = config
    }

    public func scan() -> [TranscriptFile]? {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return nil }   // enumeration failed (incl. missing root)

        var result: [TranscriptFile] = []
        for dir in projectDirs {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }   // skip this subdir, not the whole scan
            for url in entries where url.pathExtension == "jsonl" {
                let sessionId = url.deletingPathExtension().lastPathComponent
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date.distantPast
                let cwd = resolveCWD(sessionId: sessionId, url: url)
                result.append(TranscriptFile(sessionId: sessionId, lastModified: mtime, cwd: cwd))
            }
        }
        return result
    }

    private func resolveCWD(sessionId: String, url: URL) -> String? {
        if let cached = cwdCache[sessionId] { return cached }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: config.transcriptReadBytes)
        guard let raw = TranscriptDecoder.firstCWD(in: data) else { return nil }
        let standardized = PathNormalizer.standardize(raw)
        cwdCache[sessionId] = standardized
        return standardized
    }
}
