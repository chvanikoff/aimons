import XCTest
@testable import AIMonCore

final class ScaffoldTests: XCTestCase {
    func test_version_isSet() {
        // A non-empty semver-ish string; don't pin a literal so version bumps don't break the suite.
        XCTAssertFalse(AIMonCore.version.isEmpty)
        XCTAssertTrue(AIMonCore.version.contains("."))
    }
}
