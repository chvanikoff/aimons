import XCTest
import Foundation
@testable import AIMonCore

final class FileTranscriptStoreTests: XCTestCase {
    private let fm = FileManager.default

    private func makeRoot() throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("aimon-store-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(root: URL, project: String, session: String, records: [[String: Any]]) throws {
        let dir = root.appendingPathComponent(project)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let lines = try records.map { String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: dir.appendingPathComponent("\(session).jsonl"))
    }

    func test_scan_discoversTranscriptWithMtimeAndStandardizedCwd() throws {
        let root = try makeRoot(); defer { try? fm.removeItem(at: root) }
        try write(root: root, project: "-Users-roman-x", session: "abc",
                  records: [["sessionId": "abc", "cwd": "/Users/roman/x"]])
        let files = FileTranscriptStore(projectsRoot: root).scan()
        XCTAssertEqual(files?.count, 1)
        XCTAssertEqual(files?.first?.sessionId, "abc")
        XCTAssertEqual(files?.first?.cwd, PathNormalizer.standardize("/Users/roman/x"))
    }

    func test_scan_missingRoot_returnsNil() {
        let missing = fm.temporaryDirectory.appendingPathComponent("aimon-missing-\(UUID().uuidString)")
        XCTAssertNil(FileTranscriptStore(projectsRoot: missing).scan())
    }

    func test_scan_emptyRoot_returnsEmptyNotNil() throws {
        let root = try makeRoot(); defer { try? fm.removeItem(at: root) }
        XCTAssertEqual(FileTranscriptStore(projectsRoot: root).scan()?.count, 0)
    }

    func test_scan_transcriptWithoutCwd_hasNilCwd() throws {
        let root = try makeRoot(); defer { try? fm.removeItem(at: root) }
        try write(root: root, project: "-p", session: "q", records: [["type": "queue-operation", "sessionId": "q"]])
        let f = FileTranscriptStore(projectsRoot: root).scan()?.first
        XCTAssertEqual(f?.sessionId, "q")
        XCTAssertNil(f?.cwd)
    }

    func test_scan_cwdResolvedThroughSymlink() throws {
        let root = try makeRoot(); defer { try? fm.removeItem(at: root) }
        let realCwd = root.appendingPathComponent("realcwd")
        let linkCwd = root.appendingPathComponent("linkcwd")
        try fm.createDirectory(at: realCwd, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linkCwd, withDestinationURL: realCwd)
        try write(root: root, project: "-proj", session: "s", records: [["sessionId": "s", "cwd": linkCwd.path]])
        XCTAssertEqual(FileTranscriptStore(projectsRoot: root).scan()?.first?.cwd,
                       PathNormalizer.standardize(realCwd.path))
    }

    func test_scan_cachesCwdEvenIfFileLaterLosesIt() throws {
        let root = try makeRoot(); defer { try? fm.removeItem(at: root) }
        try write(root: root, project: "-p", session: "s", records: [["sessionId": "s", "cwd": "/Users/roman/x"]])
        let store = FileTranscriptStore(projectsRoot: root)
        _ = store.scan()
        try write(root: root, project: "-p", session: "s", records: [["type": "queue-operation", "sessionId": "s"]])
        XCTAssertEqual(store.scan()?.first?.cwd, PathNormalizer.standardize("/Users/roman/x"))
    }
}
