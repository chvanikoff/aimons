import XCTest
@testable import AIMonCore

final class ProjectIdentityTests: XCTestCase {
    func test_sameCWD_producesSameSeed() {
        let a = ProjectIdentity.seed(forCWD: "/Users/roman/Projects/aimon")
        let b = ProjectIdentity.seed(forCWD: "/Users/roman/Projects/aimon")
        XCTAssertEqual(a, b)
    }

    func test_differentCWDs_produceDifferentSeeds() {
        let a = ProjectIdentity.seed(forCWD: "/Users/roman/Projects/aimon")
        let b = ProjectIdentity.seed(forCWD: "/Users/roman/Projects/other")
        XCTAssertNotEqual(a, b)
    }

    func test_emptyString_isStableNonCrashing() {
        XCTAssertEqual(ProjectIdentity.seed(forCWD: ""), ProjectIdentity.seed(forCWD: ""))
    }
}
