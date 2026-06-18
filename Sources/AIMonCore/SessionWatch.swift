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
    /// Diffs `files` against `tracked` into start/end decisions. Results are sorted for
    /// determinism. A tracked session ends when its file is stale or has disappeared.
    public static func reconcile(files: [TranscriptFile],
                                 tracked: Set<String>,
                                 now: Date,
                                 liveWindow: TimeInterval,
                                 staleTimeout: TimeInterval) -> WatchDecision {
        var toStart: [String] = []
        var toEnd: [String] = []
        let byId = Dictionary(files.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })

        for f in files where !tracked.contains(f.sessionId) {
            if SessionLiveness.isLive(lastModified: f.lastModified, now: now, liveWindow: liveWindow) {
                toStart.append(f.sessionId)
            }
        }
        for id in tracked {
            if let f = byId[id] {
                if SessionLiveness.isEnded(lastModified: f.lastModified, now: now, staleTimeout: staleTimeout) {
                    toEnd.append(id)
                }
            } else {
                toEnd.append(id)   // file disappeared
            }
        }
        return WatchDecision(toStart: toStart.sorted(), toEnd: toEnd.sorted())
    }
}
