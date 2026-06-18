import XCTest
@testable import AIMonCore

final class ProcessScanResolveTests: XCTestCase {
    func test_psFailed_isNil() {
        XCTAssertNil(ProcessScan.resolveLiveCWDs(claudePIDs: nil, lsofOutput: "n/x\n"))
    }

    func test_noClaudeRunning_isTrustworthyEmpty() {
        XCTAssertEqual(ProcessScan.resolveLiveCWDs(claudePIDs: [], lsofOutput: nil), [])
    }

    func test_lsofCouldNotRun_isNil() {
        XCTAssertNil(ProcessScan.resolveLiveCWDs(claudePIDs: ["1"], lsofOutput: nil))
    }

    func test_lsofUndercount_isNil() {
        // 2 pids requested, lsof returned only 1 cwd (a pid died mid-probe) -> unreliable.
        XCTAssertNil(ProcessScan.resolveLiveCWDs(claudePIDs: ["1", "2"], lsofOutput: "p1\nn/x\n"))
    }

    func test_success_returnsCwds() {
        XCTAssertEqual(
            ProcessScan.resolveLiveCWDs(claudePIDs: ["1", "2"], lsofOutput: "p1\nn/x\np2\nn/y\n"),
            ["/x", "/y"])
    }
}
