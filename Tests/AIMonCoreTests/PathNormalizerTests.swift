import XCTest
@testable import AIMonCore

final class PathNormalizerTests: XCTestCase {
    func test_standardize_resolvesSymlinkToSameRealPath() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("aimon-pn-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real")
        let link = base.appendingPathComponent("link")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? fm.removeItem(at: base) }

        XCTAssertEqual(PathNormalizer.standardize(link.path), PathNormalizer.standardize(real.path),
                       "a symlink and its target must canonicalize to the same path")
    }

    func test_standardize_isIdempotent() {
        let once = PathNormalizer.standardize("/Users/roman/Projects/aimon")
        XCTAssertEqual(PathNormalizer.standardize(once), once)
    }
}
