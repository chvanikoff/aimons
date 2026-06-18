import XCTest
import Foundation
@testable import AIMonCore

final class SessionWatchEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let cwd = "/Users/roman/Projects/aimon"
    private let cwd2 = "/Users/roman/Projects/other"

    private func file(_ id: String, age: TimeInterval, cwd: String?) -> TranscriptFile {
        TranscriptFile(sessionId: id, lastModified: now.addingTimeInterval(-age), cwd: cwd)
    }
    private func engine() -> SessionWatchEngine { SessionWatchEngine(config: .default) }

    // MARK: - Primary path: one monster per directory, driven by live process cwds

    func test_oneProcess_spawnsOneProjectWithCountOne() {
        let out = engine().step(files: [], liveCWDs: [cwd], now: now)
        XCTAssertEqual(out.started, [ProjectRef(cwd: cwd, seed: ProjectIdentity.seed(forCWD: cwd), sessionCount: 1)])
        XCTAssertEqual(out.ended, [])
        XCTAssertEqual(out.changed, [])
    }

    func test_twoProcessesSameDir_oneMonsterCountTwo() {
        let out = engine().step(files: [], liveCWDs: [cwd, cwd], now: now)
        XCTAssertEqual(out.started.count, 1, "same dir → ONE monster, not two")
        XCTAssertEqual(out.started.first?.sessionCount, 2)
    }

    func test_secondSessionOpens_emitsChangedCount() {
        let e = engine()
        e.step(files: [], liveCWDs: [cwd], now: now)
        let out = e.step(files: [], liveCWDs: [cwd, cwd], now: now)
        XCTAssertEqual(out.started, [])
        XCTAssertEqual(out.changed, [ProjectRef(cwd: cwd, seed: ProjectIdentity.seed(forCWD: cwd), sessionCount: 2)])
    }

    func test_oneOfTwoSameDirCloses_emitsChangedNotEnded() {  // the reported bug, now well-defined
        let e = engine()
        e.step(files: [], liveCWDs: [cwd, cwd], now: now)
        let out = e.step(files: [], liveCWDs: [cwd], now: now)
        XCTAssertEqual(out.ended, [], "the monster must NOT vanish while a session is still live")
        XCTAssertEqual(out.changed.first?.sessionCount, 1)
    }

    func test_lastSessionCloses_ends() {
        let e = engine()
        e.step(files: [], liveCWDs: [cwd], now: now)
        let out = e.step(files: [], liveCWDs: [], now: now)
        XCTAssertEqual(out.ended, [cwd])
    }

    func test_distinctDirs_independentMonsters() {
        let out = engine().step(files: [], liveCWDs: [cwd, cwd2], now: now)
        XCTAssertEqual(out.started.map(\.cwd), [cwd, cwd2].sorted())
        XCTAssertTrue(out.started.allSatisfy { $0.sessionCount == 1 })
    }

    func test_idleProjectWithLiveProcess_isKept() {
        let e = engine()
        e.step(files: [], liveCWDs: [cwd], now: now)
        XCTAssertEqual(e.step(files: [], liveCWDs: [cwd], now: now), .empty)
        XCTAssertEqual(e.trackedCWDs, [cwd])
        XCTAssertEqual(e.sessionCount(forCWD: cwd), 1)
    }

    func test_seedDerivesFromCwd() {
        let out = engine().step(files: [], liveCWDs: [cwd], now: now)
        XCTAssertEqual(out.started.first?.seed, ProjectIdentity.seed(forCWD: cwd))
    }

    // MARK: - Probe-down fallback (transcript mtime)

    func test_probeNil_freshTranscript_spawns() {
        let out = engine().step(files: [file("s", age: 5, cwd: cwd)], liveCWDs: nil, now: now)
        XCTAssertEqual(out.started.map(\.cwd), [cwd])
    }

    func test_probeNil_neverDespawns_evenWhenTranscriptGoesStale() {
        // nil = "couldn't verify", not "ended". A tracked project must survive a probe outage
        // regardless of staleness; only an available probe that omits the cwd ends it.
        let e = engine()
        e.step(files: [file("s", age: 5, cwd: cwd)], liveCWDs: nil, now: now)
        let stale = e.step(files: [file("s", age: 9999, cwd: cwd)], liveCWDs: nil, now: now)
        XCTAssertEqual(stale.ended, [], "a probe outage must not despawn (prevents undercount flapping)")
        XCTAssertEqual(e.sessionCount(forCWD: cwd), 1)
        // ...but an AVAILABLE probe that omits the cwd does end it:
        let confirmed = e.step(files: [], liveCWDs: [], now: now)
        XCTAssertEqual(confirmed.ended, [cwd])
    }

    func test_probeNil_idle_isKept() {
        let e = engine()
        e.step(files: [file("s", age: 5, cwd: cwd)], liveCWDs: nil, now: now)
        let out = e.step(files: [file("s", age: 50, cwd: cwd)], liveCWDs: nil, now: now)
        XCTAssertEqual(out, .empty)
        XCTAssertEqual(e.sessionCount(forCWD: cwd), 1)
    }

    func test_probeNil_nilCwdTranscript_ignored() {
        let out = engine().step(files: [file("q", age: 1, cwd: nil)], liveCWDs: nil, now: now)
        XCTAssertEqual(out, .empty)
    }

    // MARK: - Value types

    func test_watchOutcome_empty() {
        XCTAssertTrue(WatchOutcome.empty.isEmpty)
        XCTAssertFalse(WatchOutcome(started: [ProjectRef(cwd: cwd, seed: 1, sessionCount: 1)], ended: [], changed: []).isEmpty)
    }
}
