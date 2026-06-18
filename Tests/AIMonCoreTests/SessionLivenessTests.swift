import XCTest
import Foundation
@testable import AIMonCore

final class SessionLivenessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_isLive_trueWithinWindow() {
        let modified = now.addingTimeInterval(-10)
        XCTAssertTrue(SessionLiveness.isLive(lastModified: modified, now: now, liveWindow: 30))
    }

    func test_isLive_falseBeyondWindow() {
        let modified = now.addingTimeInterval(-60)
        XCTAssertFalse(SessionLiveness.isLive(lastModified: modified, now: now, liveWindow: 30))
    }

    func test_isEnded_falseWithinTimeout() {
        let modified = now.addingTimeInterval(-30)
        XCTAssertFalse(SessionLiveness.isEnded(lastModified: modified, now: now, staleTimeout: 90))
    }

    func test_isEnded_trueBeyondTimeout() {
        let modified = now.addingTimeInterval(-120)
        XCTAssertTrue(SessionLiveness.isEnded(lastModified: modified, now: now, staleTimeout: 90))
    }
}
