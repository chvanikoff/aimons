import Foundation
import CoreGraphics

/// Tunables for session tracking, with their invariants enforced in one place so
/// production and tests share a single source of truth and can't silently drift.
public struct WatcherConfig: Equatable, Sendable {
    /// Seconds between watcher polls.
    public let pollInterval: TimeInterval
    /// A transcript modified within this window counts as freshly active (mtime spawn signal / probe-down fallback).
    public let liveWindow: TimeInterval
    /// When the process probe is unavailable, a tracked session ends after its transcript is stale this long.
    public let staleTimeout: TimeInterval
    /// Hard deadline for each `ps`/`lsof` subprocess before it's killed and the probe degrades to nil.
    public let probeTimeout: TimeInterval
    /// Max bytes read from a transcript when resolving its cwd.
    public let transcriptReadBytes: Int

    public init(pollInterval: TimeInterval = 2,
                liveWindow: TimeInterval = 30,
                staleTimeout: TimeInterval = 90,
                probeTimeout: TimeInterval = 3,
                transcriptReadBytes: Int = 262_144) {
        precondition(
            Self.isValid(liveWindow: liveWindow, staleTimeout: staleTimeout, pollInterval: pollInterval,
                         probeTimeout: probeTimeout, transcriptReadBytes: transcriptReadBytes),
            "invalid WatcherConfig: liveWindow must be >0 and < staleTimeout; pollInterval/probeTimeout >0; transcriptReadBytes >=4096")
        self.pollInterval = pollInterval
        self.liveWindow = liveWindow
        self.staleTimeout = staleTimeout
        self.probeTimeout = probeTimeout
        self.transcriptReadBytes = transcriptReadBytes
    }

    public static let `default` = WatcherConfig()

    /// Pure invariant check, shared by `init`'s precondition and tests.
    public static func isValid(liveWindow: TimeInterval, staleTimeout: TimeInterval,
                               pollInterval: TimeInterval, probeTimeout: TimeInterval,
                               transcriptReadBytes: Int) -> Bool {
        liveWindow > 0
            && staleTimeout > liveWindow
            && pollInterval > 0
            && probeTimeout > 0
            && transcriptReadBytes >= 4096
    }
}

/// Sizing/animation tunables for the rendered companion.
public struct RenderConfig: Equatable, Sendable {
    public let pixelScale: CGFloat
    public let minScale: CGFloat
    public let maxScale: CGFloat
    public let bobAmplitude: CGFloat
    public let bobDuration: TimeInterval
    public let cascadeStep: CGFloat

    public init(pixelScale: CGFloat = 16, minScale: CGFloat = 0.5, maxScale: CGFloat = 3.0,
                bobAmplitude: CGFloat = 3, bobDuration: TimeInterval = 0.7, cascadeStep: CGFloat = 40) {
        self.pixelScale = pixelScale
        self.minScale = minScale
        self.maxScale = maxScale
        self.bobAmplitude = bobAmplitude
        self.bobDuration = bobDuration
        self.cascadeStep = cascadeStep
    }

    public static let `default` = RenderConfig()
}
