import Foundation
import AIMonCore

/// Tails the active transcript of each live project and reports the latest notable activity.
/// Intended to be called on a background queue (it does filesystem I/O). Per project it resolves
/// the freshest transcript whose recorded cwd matches, caches that, and offset-tails it.
final class TranscriptActivityReader {
    private let projectsRoot: URL
    private let config: WatcherConfig
    private let tail = TranscriptTailReader()

    private var cwdCache: [String: String] = [:]   // transcript path -> standardized cwd
    private var activePath: [String: String] = [:] // project cwd -> active transcript path
    private var ticksSinceResolve: [String: Int] = [:]
    private let reResolveEvery = 10

    init(projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
         config: WatcherConfig = .default) {
        self.projectsRoot = projectsRoot
        self.config = config
    }

    func activity(forCWD cwd: String) -> SessionActivity? {
        guard let path = resolveActivePath(forCWD: cwd) else { return nil }
        let signals = tail.newLines(atPath: path).flatMap { TranscriptActivityDecoder.signals(fromLine: $0) }
        return signals.isEmpty ? nil : ActivityClassifier.activity(from: signals)
    }

    // MARK: - Resolving the active transcript (cached; periodically refreshed)

    private func resolveActivePath(forCWD cwd: String) -> String? {
        let ticks = ticksSinceResolve[cwd] ?? reResolveEvery
        if let cached = activePath[cwd], ticks < reResolveEvery {
            ticksSinceResolve[cwd] = ticks + 1
            return cached
        }
        ticksSinceResolve[cwd] = 0
        let resolved = freshestTranscript(forCWD: cwd)
        activePath[cwd] = resolved
        return resolved
    }

    private func freshestTranscript(forCWD cwd: String) -> String? {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: projectsRoot,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) else { return nil }
        var best: (path: String, mtime: Date)?
        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let files = try? fm.contentsOfDirectory(at: dir,
                                                          includingPropertiesForKeys: [.contentModificationDateKey],
                                                          options: [.skipsHiddenFiles]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard fileCWD(file.path) == cwd else { continue }
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if best == nil || mtime > best!.mtime { best = (file.path, mtime) }
            }
        }
        return best?.path
    }

    private func fileCWD(_ path: String) -> String? {
        if let cached = cwdCache[path] { return cached }
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: config.transcriptReadBytes)
        guard let raw = TranscriptDecoder.firstCWD(in: data) else { return nil }
        let standardized = PathNormalizer.standardize(raw)
        cwdCache[path] = standardized
        return standardized
    }
}
