import XCTest
import Foundation
@testable import AIMonCore

final class WatcherReconcilerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let cwd = "/Users/roman/Projects/aimon"

    private func file(_ id: String, ageSeconds: TimeInterval) -> TranscriptFile {
        TranscriptFile(sessionId: id, lastModified: now.addingTimeInterval(-ageSeconds))
    }
    private func reconcile(files: [TranscriptFile],
                           tracked: [TrackedSession],
                           liveCWDCounts: [String: Int]?) -> WatchDecision {
        WatcherReconciler.reconcile(files: files, tracked: tracked, liveCWDCounts: liveCWDCounts,
                                    now: now, liveWindow: 30, staleTimeout: 90)
    }

    // MARK: - Spawn (still mtime-gated)

    func test_newLiveFile_isStarted() {
        let d = reconcile(files: [file("s1", ageSeconds: 5)], tracked: [], liveCWDCounts: [:])
        XCTAssertEqual(d.toStart, ["s1"])
        XCTAssertEqual(d.toEnd, [])
    }

    func test_staleUntrackedFile_isIgnored() {
        let d = reconcile(files: [file("old", ageSeconds: 9999)], tracked: [], liveCWDCounts: [cwd: 1])
        XCTAssertEqual(d.toStart, [])
    }

    func test_alreadyTrackedLiveFile_isNotStartedAgain() {
        let d = reconcile(files: [file("s1", ageSeconds: 5)],
                          tracked: [TrackedSession(sessionId: "s1", cwd: cwd)], liveCWDCounts: [cwd: 1])
        XCTAssertEqual(d.toStart, [])
    }

    // MARK: - End (process-aware)

    func test_idleSessionWithLiveProcess_isKeptAlive() {  // the center-jump bug
        let d = reconcile(files: [file("s1", ageSeconds: 9999)],
                          tracked: [TrackedSession(sessionId: "s1", cwd: cwd)], liveCWDCounts: [cwd: 1])
        XCTAssertEqual(d.toEnd, [], "an idle session whose claude process is alive must not despawn")
    }

    func test_sessionWithNoLiveProcess_isEndedImmediately() {  // fast despawn on Ctrl-C
        let d = reconcile(files: [file("s1", ageSeconds: 1)],
                          tracked: [TrackedSession(sessionId: "s1", cwd: cwd)], liveCWDCounts: [:])
        XCTAssertEqual(d.toEnd, ["s1"], "no claude process for the cwd → despawn now, even if mtime is fresh")
    }

    func test_trackedFileVanished_isEnded() {
        let d = reconcile(files: [], tracked: [TrackedSession(sessionId: "gone", cwd: cwd)],
                          liveCWDCounts: [cwd: 1])
        XCTAssertEqual(d.toEnd, ["gone"])
    }

    // Count invariant: monsters for a dir == live processes there. Two transcripts,
    // one process → keep the freshest, end the stalest (the duplicate-for-this-session bug).
    func test_sharedCwd_moreTranscriptsThanProcesses_endsStalest() {
        let d = reconcile(
            files: [file("fresh", ageSeconds: 2), file("stale", ageSeconds: 200)],
            tracked: [TrackedSession(sessionId: "fresh", cwd: cwd),
                      TrackedSession(sessionId: "stale", cwd: cwd)],
            liveCWDCounts: [cwd: 1])
        XCTAssertEqual(d.toEnd, ["stale"], "with 1 process for 2 transcripts, the stalest is dropped")
    }

    func test_sharedCwd_processPerTranscript_keepsAll() {
        let d = reconcile(
            files: [file("a", ageSeconds: 2), file("b", ageSeconds: 200)],
            tracked: [TrackedSession(sessionId: "a", cwd: cwd),
                      TrackedSession(sessionId: "b", cwd: cwd)],
            liveCWDCounts: [cwd: 2])
        XCTAssertEqual(d.toEnd, [])
    }

    func test_sharedCwd_allProcessesGone_endsAll() {
        let d = reconcile(
            files: [file("a", ageSeconds: 2), file("b", ageSeconds: 2)],
            tracked: [TrackedSession(sessionId: "a", cwd: cwd),
                      TrackedSession(sessionId: "b", cwd: cwd)],
            liveCWDCounts: [:])
        XCTAssertEqual(d.toEnd, ["a", "b"])
    }

    // MARK: - Spawn gate (count-based, anti-flap)

    func test_canSpawn_allowsWhenDirHasAnUnfilledProcessSlot() {
        XCTAssertTrue(WatcherReconciler.canSpawn(cwd: cwd, trackedAtCwd: 0, liveCWDCounts: [cwd: 1]))
        XCTAssertTrue(WatcherReconciler.canSpawn(cwd: cwd, trackedAtCwd: 1, liveCWDCounts: [cwd: 2]))
    }

    func test_canSpawn_refusesWhenDirIsAlreadyAtProcessCount() {
        XCTAssertFalse(WatcherReconciler.canSpawn(cwd: cwd, trackedAtCwd: 1, liveCWDCounts: [cwd: 1]),
                       "a 2nd transcript must not spawn when 1 process already has 1 monster")
        XCTAssertFalse(WatcherReconciler.canSpawn(cwd: cwd, trackedAtCwd: 0, liveCWDCounts: [:]))
    }

    func test_canSpawn_allowsWhenProbeUnavailable() {
        XCTAssertTrue(WatcherReconciler.canSpawn(cwd: cwd, trackedAtCwd: 5, liveCWDCounts: nil))
    }

    // Regression for the flap: after Ctrl-C the process is gone but the transcript is
    // still fresh. End fires AND re-spawn is refused (0 slots) — so it stays gone.
    func test_endedSession_withFreshTranscriptButNoProcess_doesNotRespawn() {
        let d = reconcile(files: [file("s1", ageSeconds: 1)],
                          tracked: [TrackedSession(sessionId: "s1", cwd: cwd)], liveCWDCounts: [:])
        XCTAssertEqual(d.toEnd, ["s1"], "no process → end even though fresh")
        XCTAssertFalse(WatcherReconciler.canSpawn(cwd: cwd, trackedAtCwd: 0, liveCWDCounts: [:]),
                       "and the freshness must not respawn it")
    }

    // MARK: - Fallback when the process probe is unavailable (nil)

    func test_probeUnavailable_fallsBackToStaleTimeout() {
        let stale = reconcile(files: [file("s1", ageSeconds: 200)],
                              tracked: [TrackedSession(sessionId: "s1", cwd: cwd)], liveCWDCounts: nil)
        XCTAssertEqual(stale.toEnd, ["s1"])

        let fresh = reconcile(files: [file("s1", ageSeconds: 10)],
                              tracked: [TrackedSession(sessionId: "s1", cwd: cwd)], liveCWDCounts: nil)
        XCTAssertEqual(fresh.toEnd, [])
    }
}
