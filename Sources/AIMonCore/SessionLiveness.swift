import Foundation

/// Time-based judgement of whether a transcript represents an active session.
public enum SessionLiveness {
    /// A transcript is "live" if it was modified within `liveWindow` seconds of `now`.
    public static func isLive(lastModified: Date, now: Date, liveWindow: TimeInterval) -> Bool {
        now.timeIntervalSince(lastModified) <= liveWindow
    }

    /// A tracked session has "ended" if its transcript has been stale longer than `staleTimeout`.
    public static func isEnded(lastModified: Date, now: Date, staleTimeout: TimeInterval) -> Bool {
        now.timeIntervalSince(lastModified) > staleTimeout
    }
}
