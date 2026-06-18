import Foundation

/// A live project as the watcher understands it: the directory, its appearance seed, and how
/// many `claude` sessions are currently live in it. One monster represents one project; the
/// session count is context the monster can react to (e.g. "a second session just opened here").
public struct ProjectRef: Equatable, Sendable {
    public let cwd: String
    public let seed: UInt64
    public let sessionCount: Int

    public init(cwd: String, seed: UInt64, sessionCount: Int) {
        self.cwd = cwd
        self.seed = seed
        self.sessionCount = sessionCount
    }
}

/// The delta a single watcher step produces.
public struct WatchOutcome: Equatable, Sendable {
    public let started: [ProjectRef]   // projects that just became live
    public let ended: [String]         // cwds of projects no longer live
    public let changed: [ProjectRef]   // live projects whose session count changed

    public init(started: [ProjectRef], ended: [String], changed: [ProjectRef]) {
        self.started = started
        self.ended = ended
        self.changed = changed
    }

    public static let empty = WatchOutcome(started: [], ended: [], changed: [])
    public var isEmpty: Bool { started.isEmpty && ended.isEmpty && changed.isEmpty }
}

/// The stateful brain of session tracking, pure given its `step` arguments.
///
/// **Model: one monster per directory.** A directory is live while ≥1 `claude` process runs
/// in it; the monster appears on the first session and despawns when the last one closes. The
/// per-directory session count comes straight from the process probe (each live `claude`
/// process's cwd), so there is no ambiguity about "which session" — a problem macOS makes
/// unsolvable, since a process exposes its cwd but not its transcript id.
///
/// When the probe is unavailable (`liveCWDs == nil`) it degrades to transcript mtime: a
/// directory is live if it has a recently-written transcript, and ends once all of its
/// transcripts are stale.
public final class SessionWatchEngine {
    private let config: WatcherConfig
    private var tracked: [String: Int] = [:]   // cwd -> live session count

    public init(config: WatcherConfig = .default) {
        self.config = config
    }

    public var trackedCWDs: [String] { Array(tracked.keys) }
    public func sessionCount(forCWD cwd: String) -> Int? { tracked[cwd] }

    /// Advance one tick. `liveCWDs` are standardized cwds of live `claude` processes (with
    /// multiplicity), or nil if the probe failed. `now` and `files` are used only on the
    /// probe-down fallback path. Mutates internal tracking; returns the delta.
    @discardableResult
    public func step(files: [TranscriptFile], liveCWDs: [String]?, now: Date) -> WatchOutcome {
        let live = liveCWDs.map(Self.tally) ?? fallbackLiveCounts(files: files, now: now)
        return reconcile(live)
    }

    // MARK: - Internals

    private static func tally(_ cwds: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for cwd in cwds { counts[cwd, default: 0] += 1 }
        return counts
    }

    /// Probe-down fallback. A `nil` probe means "couldn't verify the live set", NOT "everything
    /// ended" — so it must be **non-destructive**: keep every currently-tracked project exactly
    /// as-is (no despawns, no count changes), and only *add* a newly-fresh transcript's directory
    /// as a new project. A genuine end is recognized later, when an available probe affirmatively
    /// omits the cwd. This is what prevents idle projects from flap-despawning during the brief
    /// `ps`/`lsof` undercounts that happen under rapid process churn.
    private func fallbackLiveCounts(files: [TranscriptFile], now: Date) -> [String: Int] {
        var live = tracked   // keep all tracked projects untouched
        var freshCount: [String: Int] = [:]
        for f in files {
            guard let cwd = f.cwd,
                  SessionLiveness.isLive(lastModified: f.lastModified, now: now, liveWindow: config.liveWindow)
            else { continue }
            freshCount[cwd, default: 0] += 1
        }
        for (cwd, count) in freshCount where live[cwd] == nil {
            live[cwd] = count   // a brand-new session can still appear during a probe outage
        }
        return live
    }

    private func reconcile(_ live: [String: Int]) -> WatchOutcome {
        var started: [ProjectRef] = []
        var changed: [ProjectRef] = []
        for (cwd, count) in live {
            let ref = ProjectRef(cwd: cwd, seed: ProjectIdentity.seed(forCWD: cwd), sessionCount: count)
            if let prev = tracked[cwd] {
                if prev != count { changed.append(ref) }
            } else {
                started.append(ref)
            }
        }
        let ended = tracked.keys.filter { live[$0] == nil }

        tracked = live
        return WatchOutcome(started: started.sorted { $0.cwd < $1.cwd },
                            ended: ended.sorted(),
                            changed: changed.sorted { $0.cwd < $1.cwd })
    }
}
