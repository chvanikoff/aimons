import XCTest
import Foundation
@testable import AIMonCore

final class SessionWatchEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let cwd = "/Users/roman/Projects/aimon"

    private func file(_ id: String, age: TimeInterval, cwd: String?) -> TranscriptFile {
        TranscriptFile(sessionId: id, lastModified: now.addingTimeInterval(-age), cwd: cwd)
    }
    private func engine() -> SessionWatchEngine { SessionWatchEngine(config: .default) }

    // MARK: - The resume bug (rank 2): stale mtime + live process must spawn

    func test_resume_staleMtimeButLiveProcess_spawns() {
        let e = engine()
        let out = e.step(files: [file("s", age: 9999, cwd: cwd)], liveCWDs: [cwd], now: now)
        XCTAssertEqual(out.started.map(\.sessionId), ["s"])
        XCTAssertEqual(out.started.first?.seed, ProjectIdentity.seed(forCWD: cwd))
    }

    // MARK: - The three already-fixed bugs, as multi-tick regressions

    func test_idleSessionWithLiveProcess_isKept() {
        let e = engine()
        e.step(files: [file("s", age: 1, cwd: cwd)], liveCWDs: [cwd], now: now)
        let out = e.step(files: [file("s", age: 9999, cwd: cwd)], liveCWDs: [cwd], now: now)
        XCTAssertEqual(out, .empty)
        XCTAssertTrue(e.isTracking("s"))
    }

    func test_ctrlC_endsThenStaysGone_noFlap() {
        let e = engine()
        let t1 = e.step(files: [file("s", age: 1, cwd: cwd)], liveCWDs: [cwd], now: now)
        XCTAssertEqual(t1.started.map(\.sessionId), ["s"])
        let t2 = e.step(files: [file("s", age: 2, cwd: cwd)], liveCWDs: [], now: now)  // process died
        XCTAssertEqual(t2.ended, ["s"])
        let t3 = e.step(files: [file("s", age: 3, cwd: cwd)], liveCWDs: [], now: now)  // still fresh, no process
        XCTAssertEqual(t3, .empty, "freshness must not respawn an ended session")
        XCTAssertFalse(e.isTracking("s"))
    }

    func test_duplicateSibling_keepsFreshestEndsStalest() {
        let e = engine()
        e.step(files: [file("fe", age: 1, cwd: cwd), file("ca", age: 2, cwd: cwd)],
               liveCWDs: [cwd, cwd], now: now)                                          // 2 processes -> both
        let out = e.step(files: [file("fe", age: 1, cwd: cwd), file("ca", age: 50, cwd: cwd)],
                         liveCWDs: [cwd], now: now)                                      // down to 1
        XCTAssertEqual(out.ended, ["ca"], "the stalest twin is dropped to match process count")
        XCTAssertTrue(e.isTracking("fe"))
    }

    // MARK: - Count invariant

    func test_twoFreshSameCwd_oneProcess_spawnsExactlyTheFreshest() {
        let e = engine()
        let out = e.step(files: [file("A", age: 5, cwd: cwd), file("B", age: 1, cwd: cwd)],
                         liveCWDs: [cwd], now: now)
        XCTAssertEqual(out.started.map(\.sessionId), ["B"], "1 process -> only the freshest spawns")
    }

    func test_twoProcessesTwoSessions_spawnsBoth() {
        let e = engine()
        let out = e.step(files: [file("A", age: 5, cwd: cwd), file("B", age: 1, cwd: cwd)],
                         liveCWDs: [cwd, cwd], now: now)
        XCTAssertEqual(out.started.map(\.sessionId), ["A", "B"])
    }

    func test_noLiveProcessForCwd_endsTracked() {
        let e = engine()
        e.step(files: [file("s", age: 1, cwd: cwd)], liveCWDs: [cwd], now: now)
        let out = e.step(files: [file("s", age: 1, cwd: cwd)], liveCWDs: ["/elsewhere"], now: now)
        XCTAssertEqual(out.ended, ["s"])
    }

    func test_vanishedTrackedFile_isEnded() {
        let e = engine()
        e.step(files: [file("s", age: 1, cwd: cwd)], liveCWDs: [cwd], now: now)
        let out = e.step(files: [], liveCWDs: [cwd], now: now)
        XCTAssertEqual(out.ended, ["s"])
    }

    func test_fileWithNilCwd_neverSpawns() {
        let e = engine()
        let out = e.step(files: [file("q", age: 1, cwd: nil)], liveCWDs: [cwd], now: now)
        XCTAssertEqual(out, .empty)
    }

    // MARK: - Probe-down fallback

    func test_probeNil_fallsBackToMtime_freshSpawnsStaleEnds() {
        let e = engine()
        let started = e.step(files: [file("s", age: 5, cwd: cwd)], liveCWDs: nil, now: now)
        XCTAssertEqual(started.started.map(\.sessionId), ["s"])
        let kept = e.step(files: [file("s", age: 10, cwd: cwd)], liveCWDs: nil, now: now)
        XCTAssertEqual(kept, .empty)
        let ended = e.step(files: [file("s", age: 200, cwd: cwd)], liveCWDs: nil, now: now)
        XCTAssertEqual(ended.ended, ["s"])
    }

    func test_probeNil_staleUntracked_doesNotSpawn() {
        let e = engine()
        XCTAssertEqual(e.step(files: [file("s", age: 9999, cwd: cwd)], liveCWDs: nil, now: now), .empty)
    }
}
