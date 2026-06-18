import XCTest
import Foundation
@testable import AIMonCore

final class TranscriptActivityTests: XCTestCase {
    // MARK: - Signal decoding

    func test_signals_editTool() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/roman/Projects/aimon/Sources/x.swift"}}],"stop_reason":"tool_use"}}"#
        XCTAssertEqual(TranscriptActivityDecoder.signals(fromLine: line), [.toolUse(name: "Edit", target: "x.swift")])
    }

    func test_signals_bashCommandTruncated() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"swift test --filter Foo"}}]}}"#
        XCTAssertEqual(TranscriptActivityDecoder.signals(fromLine: line), [.toolUse(name: "Bash", target: "swift test --filter Foo")])
    }

    func test_signals_toolErrorFromUserLine() {
        let line = #"{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"boom"}]}}"#
        XCTAssertEqual(TranscriptActivityDecoder.signals(fromLine: line), [.toolError])
    }

    func test_signals_endTurn() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text"}],"stop_reason":"end_turn"}}"#
        XCTAssertEqual(TranscriptActivityDecoder.signals(fromLine: line), [.turnEnded])
    }

    func test_signals_ignoresIrrelevant() {
        XCTAssertEqual(TranscriptActivityDecoder.signals(fromLine: #"{"type":"queue-operation"}"#), [])
        XCTAssertEqual(TranscriptActivityDecoder.signals(fromLine: "not json"), [])
    }

    // MARK: - Classification (salience)

    func test_classify_errorBeatsEverything() {
        let signals: [TranscriptSignal] = [.toolUse(name: "Edit", target: "x"), .toolError, .turnEnded]
        XCTAssertEqual(ActivityClassifier.activity(from: signals), .error)
    }

    func test_classify_testCommandIsTesting() {
        XCTAssertEqual(ActivityClassifier.activity(from: [.toolUse(name: "Bash", target: "npm test")]), .testing)
    }

    func test_classify_bashIsRunning() {
        XCTAssertEqual(ActivityClassifier.activity(from: [.toolUse(name: "Bash", target: "ls -la")]), .running(command: "ls -la"))
    }

    func test_classify_editIsEditing() {
        XCTAssertEqual(ActivityClassifier.activity(from: [.toolUse(name: "Write", target: "a.swift")]), .editing(file: "a.swift"))
    }

    func test_classify_readsAreNotNotable() {
        XCTAssertNil(ActivityClassifier.activity(from: [.toolUse(name: "Read", target: "x"), .toolUse(name: "Grep", target: nil)]))
    }

    func test_classify_endTurnIsWaiting() {
        XCTAssertEqual(ActivityClassifier.activity(from: [.turnEnded]), .waiting)
    }

    // MARK: - Tail reader

    func test_tailReader_primesToEOFThenReturnsOnlyNewCompleteLines() throws {
        let fm = FileManager.default
        let path = fm.temporaryDirectory.appendingPathComponent("aimon-tail-\(UUID().uuidString).jsonl").path
        try "old line 1\nold line 2\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(atPath: path) }

        let reader = TranscriptTailReader()
        XCTAssertEqual(reader.newLines(atPath: path), [], "first sight primes to EOF; no history replay")

        let handle = FileHandle(forWritingAtPath: path)!
        handle.seekToEndOfFile()
        handle.write(Data("new line 1\nnew line 2\npartial".utf8))   // trailing partial (no newline)
        try? handle.close()

        XCTAssertEqual(reader.newLines(atPath: path), ["new line 1", "new line 2"], "partial trailing line withheld")

        // complete the partial line
        let h2 = FileHandle(forWritingAtPath: path)!
        h2.seekToEndOfFile()
        h2.write(Data(" finished\n".utf8))
        try? h2.close()
        XCTAssertEqual(reader.newLines(atPath: path), ["partial finished"])
    }
}
