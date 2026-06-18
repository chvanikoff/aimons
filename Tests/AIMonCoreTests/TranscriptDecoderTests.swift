import XCTest
@testable import AIMonCore

final class TranscriptDecoderTests: XCTestCase {
    func test_userLine_extractsSessionIdAndCWD() {
        let line = #"{"type":"user","sessionId":"abc-123","cwd":"/Users/roman/Projects/aimon","timestamp":"2026-06-18T15:00:00Z","message":{"role":"user","content":"hi"},"gitBranch":"main"}"#
        let meta = TranscriptDecoder.meta(fromLine: line)
        XCTAssertEqual(meta?.sessionId, "abc-123")
        XCTAssertEqual(meta?.cwd, "/Users/roman/Projects/aimon")
    }

    func test_titleLine_hasSessionIdButNoCWD() {
        let line = #"{"type":"ai-title","sessionId":"abc-123","aiTitle":"Some title"}"#
        let meta = TranscriptDecoder.meta(fromLine: line)
        XCTAssertEqual(meta?.sessionId, "abc-123")
        XCTAssertNil(meta?.cwd)
    }

    func test_blankLine_isNil() {
        XCTAssertNil(TranscriptDecoder.meta(fromLine: ""))
        XCTAssertNil(TranscriptDecoder.meta(fromLine: "   "))
    }

    func test_garbageLine_isNil() {
        XCTAssertNil(TranscriptDecoder.meta(fromLine: "not json at all"))
    }

    func test_objectWithoutSessionId_isNil() {
        XCTAssertNil(TranscriptDecoder.meta(fromLine: #"{"type":"summary"}"#))
    }
}
