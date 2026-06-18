import XCTest
@testable import AIMonCore

final class ProcessScanResolveTests: XCTestCase {
    func test_psFailed_isNil() {
        XCTAssertNil(ProcessScan.resolveLiveCWDs(claudePIDs: nil, lsofOutput: "n/x\n", lsofExitOK: true))
    }

    func test_noClaudeRunning_isTrustworthyEmpty() {
        XCTAssertEqual(ProcessScan.resolveLiveCWDs(claudePIDs: [], lsofOutput: nil, lsofExitOK: false), [])
    }

    func test_lsofFailed_isNil() {
        XCTAssertNil(ProcessScan.resolveLiveCWDs(claudePIDs: ["1"], lsofOutput: nil, lsofExitOK: false))
        XCTAssertNil(ProcessScan.resolveLiveCWDs(claudePIDs: ["1"], lsofOutput: "p1\nn/x\n", lsofExitOK: false))
    }

    func test_lsofUndercount_isNil() {
        // 2 pids requested, lsof returned only 1 cwd (a pid died mid-probe) -> unreliable.
        XCTAssertNil(ProcessScan.resolveLiveCWDs(claudePIDs: ["1", "2"], lsofOutput: "p1\nn/x\n", lsofExitOK: true))
    }

    func test_success_returnsCwds() {
        XCTAssertEqual(
            ProcessScan.resolveLiveCWDs(claudePIDs: ["1", "2"], lsofOutput: "p1\nn/x\np2\nn/y\n", lsofExitOK: true),
            ["/x", "/y"])
    }
}
