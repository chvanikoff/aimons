import XCTest
@testable import AIMonCore

final class ProcessScanTests: XCTestCase {
    // Shaped after real `ps -axww -o pid= -o command=` output on macOS.
    private let psOutput = """
      59677 claude --enable-auto-mode
      53276 /Applications/Codex.app/Contents/Resources/cua_node/bin/node_repl
      53433 node /Users/roman/.npm/_npx/eea2bd7412d4593b/node_modules/.bin/context7-mcp
       1554 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer) --type=renderer
      71002 /Users/roman/.local/bin/claude
      72000 node /opt/homebrew/lib/node_modules/claude-bridge/index.js
    """

    func test_matchesBareClaudeInvocation() {
        XCTAssertTrue(ProcessScan.claudePIDs(fromPS: psOutput).contains("59677"))
    }

    func test_matchesPathInvokedClaude() {
        XCTAssertTrue(ProcessScan.claudePIDs(fromPS: psOutput).contains("71002"))
    }

    func test_excludesDesktopAppAndNodeServers() {
        let pids = ProcessScan.claudePIDs(fromPS: psOutput)
        XCTAssertFalse(pids.contains("1554"), "desktop 'Claude Helper' must not match")
        XCTAssertFalse(pids.contains("53276"), "node_repl must not match")
        XCTAssertFalse(pids.contains("53433"), "node MCP server must not match")
        XCTAssertFalse(pids.contains("72000"), "node script whose path contains 'claude' must not match")
    }

    func test_exactPidSet() {
        XCTAssertEqual(ProcessScan.claudePIDs(fromPS: psOutput), ["59677", "71002"])
    }

    func test_parsesCWDsFromLSOF() {
        let lsof = """
        p59677
        n/Users/roman/Projects/aimon
        p71002
        n/Users/roman/Projects/other
        """
        XCTAssertEqual(ProcessScan.cwds(fromLSOF: lsof),
                       ["/Users/roman/Projects/aimon", "/Users/roman/Projects/other"])
    }

    func test_countsConcurrentSessionsSharingACwd() {
        let counts = ProcessScan.counts(of: [
            "/Users/roman/Projects/aimon",
            "/Users/roman/Projects/aimon",
            "/Users/roman/Projects/other",
        ])
        XCTAssertEqual(counts["/Users/roman/Projects/aimon"], 2)
        XCTAssertEqual(counts["/Users/roman/Projects/other"], 1)
    }
}
