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
