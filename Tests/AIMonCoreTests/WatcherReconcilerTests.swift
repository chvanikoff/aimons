import XCTest
import Foundation
@testable import AIMonCore

final class WatcherReconcilerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func file(_ id: String, ageSeconds: TimeInterval) -> TranscriptFile {
        TranscriptFile(sessionId: id, lastModified: now.addingTimeInterval(-ageSeconds))
    }

    func test_newLiveFile_isStarted() {
        let d = WatcherReconciler.reconcile(files: [file("s1", ageSeconds: 5)],
                                            tracked: [], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toStart, ["s1"])
        XCTAssertEqual(d.toEnd, [])
    }

    func test_staleFile_notTracked_isIgnored() {
        let d = WatcherReconciler.reconcile(files: [file("old", ageSeconds: 9999)],
                                            tracked: [], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toStart, [])
        XCTAssertEqual(d.toEnd, [])
    }

    func test_trackedFreshFile_isNotEnded() {
        let d = WatcherReconciler.reconcile(files: [file("s1", ageSeconds: 10)],
                                            tracked: ["s1"], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toStart, [])
        XCTAssertEqual(d.toEnd, [])
    }

    func test_trackedStaleFile_isEnded() {
        let d = WatcherReconciler.reconcile(files: [file("s1", ageSeconds: 200)],
                                            tracked: ["s1"], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toEnd, ["s1"])
    }

    func test_trackedFileVanished_isEnded() {
        let d = WatcherReconciler.reconcile(files: [],
                                            tracked: ["gone"], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toEnd, ["gone"])
    }

    func test_alreadyTrackedLiveFile_isNotStartedAgain() {
        let d = WatcherReconciler.reconcile(files: [file("s1", ageSeconds: 5)],
                                            tracked: ["s1"], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toStart, [])
    }
}
