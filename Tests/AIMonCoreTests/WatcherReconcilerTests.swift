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

    // Two sessions share a project; one ends → only 1 live process for 2 tracked.
    // Ambiguous, so fall back to staleness: the stale one ends, the fresh one survives.
    func test_sharedCwd_oneProcessGone_endsStaleNotFresh() {
        let d = reconcile(
            files: [file("fresh", ageSeconds: 2), file("stale", ageSeconds: 200)],
            tracked: [TrackedSession(sessionId: "fresh", cwd: cwd),
                      TrackedSession(sessionId: "stale", cwd: cwd)],
            liveCWDCounts: [cwd: 1])
        XCTAssertEqual(d.toEnd, ["stale"])
    }

    func test_sharedCwd_bothProcessesAlive_keepsBoth() {
        let d = reconcile(
            files: [file("a", ageSeconds: 2), file("b", ageSeconds: 200)],
            tracked: [TrackedSession(sessionId: "a", cwd: cwd),
                      TrackedSession(sessionId: "b", cwd: cwd)],
            liveCWDCounts: [cwd: 2])
        XCTAssertEqual(d.toEnd, [])
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
