import XCTest
import Foundation
@testable import AIMonCore

final class SessionRefTests: XCTestCase {
    func test_sessionRef_seedDerivesFromCwdViaProjectIdentity() {
        let cwd = "/Users/roman/Projects/aimon"
        let ref = SessionRef(sessionId: "s", cwd: cwd, seed: ProjectIdentity.seed(forCWD: cwd))
        XCTAssertEqual(ref.seed, ProjectIdentity.seed(forCWD: cwd))
    }

    func test_transcriptFile_cwdDefaultsToNil() {
        XCTAssertNil(TranscriptFile(sessionId: "s", lastModified: Date()).cwd)
    }

    func test_transcriptFile_carriesCwdWhenProvided() {
        XCTAssertEqual(TranscriptFile(sessionId: "s", lastModified: Date(), cwd: "/x").cwd, "/x")
    }

    func test_watchOutcome_empty() {
        XCTAssertEqual(WatchOutcome.empty, WatchOutcome(started: [], ended: []))
    }
}
