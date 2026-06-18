import Foundation

/// A transcript file as seen by the watcher: its session id, last-modified time, and
/// resolved (standardized) cwd. `cwd` is nil when not yet resolvable (e.g. a record
/// carrying it hasn't been written, or the file is a cwd-less queue-operation transcript).
///
/// The decision logic that consumes these lives in `SessionWatchEngine`.
public struct TranscriptFile: Equatable, Sendable {
    public let sessionId: String
    public let lastModified: Date
    public let cwd: String?

    public init(sessionId: String, lastModified: Date, cwd: String? = nil) {
        self.sessionId = sessionId
        self.lastModified = lastModified
        self.cwd = cwd
    }
}
