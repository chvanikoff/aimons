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
    /// Spawn and end use the *same* signal — a live `claude` process backing the
    /// session's directory — so they can't fight and flap. `liveCWDCounts` maps a
    /// cwd to how many live processes run there; `nil` means the probe was
    /// unavailable, so we degrade to the mtime timeout.
    ///
    /// `toStart` here is only a *candidate* list (freshly written, untracked); the
    /// watcher applies `shouldSpawn` once it has resolved each candidate's cwd,
    /// since `TranscriptFile` doesn't carry one. Ending:
    ///   - file vanished            → end
    ///   - no live process for cwd  → end, and stays ended (freshness can't resurrect it)
    ///   - any live process for cwd → keep (idle-safe; all same-dir twins persist
    ///                                until the last process for that dir exits)
    ///   - probe unavailable        → fall back to the mtime stale timeout
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
        for t in tracked {
            guard let f = byId[t.sessionId] else { toEnd.append(t.sessionId); continue }  // vanished
            if let counts = liveCWDCounts {
                if (counts[t.cwd] ?? 0) == 0 { toEnd.append(t.sessionId) }                // no live claude here
            } else if SessionLiveness.isEnded(lastModified: f.lastModified, now: now, staleTimeout: staleTimeout) {
                toEnd.append(t.sessionId)                                                  // probe down → mtime fallback
            }
        }

        return WatchDecision(toStart: toStart.sorted(), toEnd: toEnd.sorted())
    }

    /// Whether a freshly-detected transcript at `cwd` should actually spawn: only if a
    /// live `claude` process backs that directory, so an ended-but-still-fresh transcript
    /// can't respawn. `nil` counts (probe unavailable) → allow (mtime-only behaviour).
    public static func shouldSpawn(cwd: String, liveCWDCounts: [String: Int]?) -> Bool {
        guard let counts = liveCWDCounts else { return true }
        return (counts[cwd] ?? 0) > 0
    }
}
