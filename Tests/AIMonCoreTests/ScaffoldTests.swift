import XCTest
@testable import AIMonCore

final class ScaffoldTests: XCTestCase {
    func test_version_isSet() {
        XCTAssertEqual(AIMonCore.version, "0.1.0")
    }
}
