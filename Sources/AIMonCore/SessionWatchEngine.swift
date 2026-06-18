import Foundation

/// A live session as the watcher understands it: stable id, the directory it runs in,
/// and the appearance seed derived from that directory. This is the minimal, forward-
/// compatible "started" payload — the seed of the richer SessionEvent stream M4 will add.
public struct SessionRef: Equatable, Sendable {
    public let sessionId: String
    public let cwd: String
    public let seed: UInt64

    public init(sessionId: String, cwd: String, seed: UInt64) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.seed = seed
    }
}

/// The delta a single watcher step produces: sessions that just appeared and ids that ended.
public struct WatchOutcome: Equatable, Sendable {
    public let started: [SessionRef]
    public let ended: [String]

    public init(started: [SessionRef], ended: [String]) {
        self.started = started
        self.ended = ended
    }

    public static let empty = WatchOutcome(started: [], ended: [])
}

/// The stateful brain of session tracking, pure given its `step` arguments.
///
/// One unified rule replaces the old spawn-candidate + canSpawn split that bred the
/// signal-asymmetry bugs: **the monsters for a directory are the `P` most-recently-
/// modified transcripts there, where `P` is the live `claude` process count for that
/// directory.** Spawn and end are two sides of the same membership decision, so they
/// cannot disagree (no idle false-despawn, no Ctrl-C flap, no duplicate sibling, and a
/// resumed/idle session with a free process slot spawns even though its mtime is stale).
///
/// When the probe is unavailable (`liveCWDs == nil`) it degrades to the mtime heuristic:
/// spawn fresh untracked transcripts, end tracked ones gone stale.
public final class SessionWatchEngine {
    private let config: WatcherConfig
    private var trackedById: [String: SessionRef] = [:]

    public init(config: WatcherConfig = .default) {
        self.config = config
    }

    /// Currently-tracked sessions (order unspecified).
    public var tracked: [SessionRef] { Array(trackedById.values) }
    public func isTracking(_ sessionId: String) -> Bool { trackedById[sessionId] != nil }

    /// Advance one tick. `liveCWDs` are standardized cwds of live `claude` processes
    /// (with multiplicity), or nil if the probe failed. `now` is used only on the
    /// probe-down fallback path. Mutates internal tracking; returns the delta.
    @discardableResult
    public func step(files: [TranscriptFile], liveCWDs: [String]?, now: Date) -> WatchOutcome {
        let filesById = Dictionary(files.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
        let outcome = liveCWDs.map { decideProcessAware(files: files, filesById: filesById, liveCWDs: $0) }
            ?? decideMtimeFallback(files: files, filesById: filesById, now: now)
        for id in outcome.ended { trackedById[id] = nil }
        for ref in outcome.started { trackedById[ref.sessionId] = ref }
        return outcome
    }

    // MARK: - Decisions (pure; no mutation of trackedById here)

    private func decideProcessAware(files: [TranscriptFile],
                                    filesById: [String: TranscriptFile],
                                    liveCWDs: [String]) -> WatchOutcome {
        var counts: [String: Int] = [:]
        for cwd in liveCWDs { counts[cwd, default: 0] += 1 }

        let trackedIds = Set(trackedById.keys)
        var byCWD: [String: [(id: String, mtime: Date, tracked: Bool)]] = [:]
        var ended: [String] = []

        // Tracked sessions group under their KNOWN cwd; a vanished file ends immediately.
        for (id, ref) in trackedById {
            if let f = filesById[id] {
                byCWD[ref.cwd, default: []].append((id, f.lastModified, true))
            } else {
                ended.append(id)
            }
        }
        // Untracked files join only if their cwd is resolvable.
        for f in files where !trackedIds.contains(f.sessionId) {
            guard let cwd = f.cwd else { continue }
            byCWD[cwd, default: []].append((f.sessionId, f.lastModified, false))
        }

        var started: [SessionRef] = []
        for (cwd, members) in byCWD {
            let keep = counts[cwd] ?? 0
            let ranked = members.sorted { a, b in
                a.mtime != b.mtime ? a.mtime > b.mtime : a.id < b.id   // freshest first, id tiebreak
            }
            let keptIds = Set(ranked.prefix(keep).map(\.id))
            for m in members {
                if m.tracked {
                    if !keptIds.contains(m.id) { ended.append(m.id) }       // evicted
                } else if keptIds.contains(m.id) {
                    started.append(SessionRef(sessionId: m.id, cwd: cwd,
                                              seed: ProjectIdentity.seed(forCWD: cwd)))
                }
            }
        }
        return WatchOutcome(started: started.sorted { $0.sessionId < $1.sessionId }, ended: ended.sorted())
    }

    private func decideMtimeFallback(files: [TranscriptFile],
                                     filesById: [String: TranscriptFile],
                                     now: Date) -> WatchOutcome {
        let trackedIds = Set(trackedById.keys)
        var started: [SessionRef] = []
        var ended: [String] = []

        for f in files where !trackedIds.contains(f.sessionId) {
            guard let cwd = f.cwd else { continue }
            if SessionLiveness.isLive(lastModified: f.lastModified, now: now, liveWindow: config.liveWindow) {
                started.append(SessionRef(sessionId: f.sessionId, cwd: cwd,
                                          seed: ProjectIdentity.seed(forCWD: cwd)))
            }
        }
        for id in trackedById.keys {
            if let f = filesById[id] {
                if SessionLiveness.isEnded(lastModified: f.lastModified, now: now, staleTimeout: config.staleTimeout) {
                    ended.append(id)
                }
            } else {
                ended.append(id)
            }
        }
        return WatchOutcome(started: started.sorted { $0.sessionId < $1.sessionId }, ended: ended.sorted())
    }
}
