import Foundation

/// A transcript file as seen by the watcher: its session id and last-modified time.
public struct TranscriptFile: Equatable {
    public let sessionId: String
    public let lastModified: Date

    public init(sessionId: String, lastModified: Date) {
        self.sessionId = sessionId
        self.lastModified = lastModified
    }
}

/// A session the watcher is currently tracking, with the cwd it was started in.
/// The cwd lets the reconciler check whether a live `claude` process still backs it.
public struct TrackedSession: Equatable {
    public let sessionId: String
    public let cwd: String

    public init(sessionId: String, cwd: String) {
        self.sessionId = sessionId
        self.cwd = cwd
    }
}

/// What the watcher should do this tick.
public struct WatchDecision: Equatable {
    public let toStart: [String]   // session ids newly live
    public let toEnd: [String]     // tracked session ids now ended

    public init(toStart: [String], toEnd: [String]) {
        self.toStart = toStart
        self.toEnd = toEnd
    }
}

public enum WatcherReconciler {
    /// Diffs transcript `files` and live-process info against `tracked` sessions.
    ///
    /// The invariant: **the number of monsters for a directory equals the number of
    /// live `claude` processes in it.** A process exposes only its cwd, not which
    /// session it is, so when several transcripts share a directory we can't map a
    /// process to a specific one — instead we keep the `P` most-recently-active
    /// sessions there (P = live process count) and end the rest. This is idle-safe
    /// (a lone live session is never stale-despawned) and flap-free (spawn obeys the
    /// same count, so an ended-but-still-fresh transcript can't resurrect).
    ///
    /// `liveCWDCounts` maps cwd → live process count; `nil` means the probe was
    /// unavailable, so we degrade to the per-session mtime stale timeout.
    ///
    /// `toStart` is only a *candidate* list (freshly written, untracked); the watcher
    /// applies `canSpawn` once it has resolved each candidate's cwd, since
    /// `TranscriptFile` doesn't carry one.
    public static func reconcile(files: [TranscriptFile],
                                 tracked: [TrackedSession],
                                 liveCWDCounts: [String: Int]?,
                                 now: Date,
                                 liveWindow: TimeInterval,
                                 staleTimeout: TimeInterval) -> WatchDecision {
        let trackedIds = Set(tracked.map(\.sessionId))
        let byId = Dictionary(files.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })

        var toStart: [String] = []
        for f in files where !trackedIds.contains(f.sessionId) {
            if SessionLiveness.isLive(lastModified: f.lastModified, now: now, liveWindow: liveWindow) {
                toStart.append(f.sessionId)
            }
        }

        var toEnd: [String] = []
        guard let counts = liveCWDCounts else {
            for t in tracked {                                       // probe down → per-session mtime fallback
                guard let f = byId[t.sessionId] else { toEnd.append(t.sessionId); continue }
                if SessionLiveness.isEnded(lastModified: f.lastModified, now: now, staleTimeout: staleTimeout) {
                    toEnd.append(t.sessionId)
                }
            }
            return WatchDecision(toStart: toStart.sorted(), toEnd: toEnd.sorted())
        }

        var byCWD: [String: [TrackedSession]] = [:]
        for t in tracked { byCWD[t.cwd, default: []].append(t) }
        for (cwd, group) in byCWD {
            var present: [(id: String, mtime: Date)] = []
            for t in group {
                if let f = byId[t.sessionId] { present.append((t.sessionId, f.lastModified)) }
                else { toEnd.append(t.sessionId) }                  // file vanished → end unconditionally
            }
            let keep = counts[cwd] ?? 0                             // monsters here == live processes here
            if present.count > keep {
                let ranked = present.sorted { ($0.mtime, $0.id) < ($1.mtime, $1.id) }  // stalest first
                for i in 0..<(present.count - keep) { toEnd.append(ranked[i].id) }
            }
        }

        return WatchDecision(toStart: toStart.sorted(), toEnd: toEnd.sorted())
    }

    /// Whether a freshly-detected transcript at `cwd` should actually spawn: only if the
    /// directory has an unfilled process slot (`trackedAtCwd < live processes there`), so
    /// monster count never exceeds process count and an ended transcript can't respawn.
    /// `nil` counts (probe unavailable) → allow (mtime-only behaviour).
    public static func canSpawn(cwd: String, trackedAtCwd: Int, liveCWDCounts: [String: Int]?) -> Bool {
        guard let counts = liveCWDCounts else { return true }
        return trackedAtCwd < (counts[cwd] ?? 0)
    }
}
