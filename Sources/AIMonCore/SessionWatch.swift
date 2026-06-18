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
    /// Spawning is still mtime-gated: only a freshly written, untracked transcript
    /// starts a session (so dormant old transcripts in a live project don't wake up).
    ///
    /// Ending is process-aware. `liveCWDCounts` maps each cwd to how many live
    /// `claude` processes run there; `nil` means the probe was unavailable, in which
    /// case we fall back to the pure mtime timeout (old behaviour). With the probe:
    ///   - file vanished              → end
    ///   - no live process for cwd    → end now (fast despawn on Ctrl-C)
    ///   - procs ≥ tracked-in-cwd     → keep (every session is backed; idle is safe)
    ///   - 0 < procs < tracked-in-cwd → ambiguous (multiple sessions share a project,
    ///                                  one ended) → fall back to the stale timeout
    public static func reconcile(files: [TranscriptFile],
                                 tracked: [TrackedSession],
                                 liveCWDCounts: [String: Int]?,
                                 now: Date,
                                 liveWindow: TimeInterval,
                                 staleTimeout: TimeInterval) -> WatchDecision {
        let trackedIds = Set(tracked.map(\.sessionId))
        let byId = Dictionary(files.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })

        var trackedPerCWD: [String: Int] = [:]
        for t in tracked { trackedPerCWD[t.cwd, default: 0] += 1 }

        var toStart: [String] = []
        for f in files where !trackedIds.contains(f.sessionId) {
            if SessionLiveness.isLive(lastModified: f.lastModified, now: now, liveWindow: liveWindow) {
                toStart.append(f.sessionId)
            }
        }

        var toEnd: [String] = []
        for t in tracked {
            guard let f = byId[t.sessionId] else { toEnd.append(t.sessionId); continue }  // vanished

            guard let counts = liveCWDCounts else {                                        // probe unavailable
                if SessionLiveness.isEnded(lastModified: f.lastModified, now: now, staleTimeout: staleTimeout) {
                    toEnd.append(t.sessionId)
                }
                continue
            }

            let procs = counts[t.cwd] ?? 0
            let trackedHere = trackedPerCWD[t.cwd] ?? 1
            if procs == 0 {
                toEnd.append(t.sessionId)                                                  // CLI gone → fast despawn
            } else if procs >= trackedHere {
                continue                                                                   // backed → keep (idle safe)
            } else if SessionLiveness.isEnded(lastModified: f.lastModified, now: now, staleTimeout: staleTimeout) {
                toEnd.append(t.sessionId)                                                   // ambiguous → stale backstop
            }
        }

        return WatchDecision(toStart: toStart.sorted(), toEnd: toEnd.sorted())
    }
}
