import XCTest
import Foundation
@testable import AIMonCore

final class TranscriptCWDScanTests: XCTestCase {
    func test_firstCWD_findsCwdEvenWhenAnEarlierLineHasMultibyteContent() {
        let l0 = #"{"type":"queue-operation","note":"café ☕ — long unicode preamble"}"#
        let l1 = #"{"type":"user","sessionId":"s","cwd":"/Users/roman/Projects/aimon"}"#
        let data = Data((l0 + "\n" + l1 + "\n").utf8)
        XCTAssertEqual(TranscriptDecoder.firstCWD(in: data), "/Users/roman/Projects/aimon")
    }

    func test_firstCWD_nilWhenNoCwdPresent() {
        XCTAssertNil(TranscriptDecoder.firstCWD(in: Data(#"{"type":"queue-operation","sessionId":"s"}"#.utf8)))
    }

    func test_firstCWD_returnsFirstCwdNotLater() {
        let data = Data((#"{"cwd":"/first"}"# + "\n" + #"{"cwd":"/second"}"# + "\n").utf8)
        XCTAssertEqual(TranscriptDecoder.firstCWD(in: data), "/first")
    }

    func test_firstCWD_skipsTruncatedTrailingLine() {
        let good = #"{"sessionId":"s","cwd":"/x"}"#
        let truncated = #"{"type":"user","cw"#   // appended-live tail, no newline
        let data = Data((good + "\n" + truncated).utf8)
        XCTAssertEqual(TranscriptDecoder.firstCWD(in: data), "/x")
    }

    func test_firstCWD_emptyDataIsNil() {
        XCTAssertNil(TranscriptDecoder.firstCWD(in: Data()))
    }
}
