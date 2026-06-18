import XCTest
import CoreGraphics
@testable import AIMonCore

final class WindowGeometryTests: XCTestCase {
    func test_unionRect_combinesRects() {
        let u = WindowGeometry.unionRect([
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
        ])
        XCTAssertEqual(u, CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    func test_unionRect_emptyIsNil() {
        XCTAssertNil(WindowGeometry.unionRect([]))
    }

    func test_clamp_pushesWindowBackOntoScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let off = CGRect(x: 950, y: -50, width: 100, height: 100)   // off right & bottom
        let c = WindowGeometry.clamp(off, within: [screen])
        XCTAssertEqual(c, CGRect(x: 900, y: 0, width: 100, height: 100))
    }

    func test_clamp_leavesOnscreenWindowUntouched() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let win = CGRect(x: 100, y: 100, width: 100, height: 100)
        XCTAssertEqual(WindowGeometry.clamp(win, within: [screen]), win)
    }

    func test_clamp_allowsSpanningBetweenAdjacentScreens() {
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let win = CGRect(x: 950, y: 100, width: 100, height: 100)   // straddles x=1000 border
        XCTAssertEqual(WindowGeometry.clamp(win, within: [left, right]), win)
    }

    func test_zoom_aboutCenter_keepsCenter() {
        let f = CGRect(x: 0, y: 0, width: 100, height: 100)
        let z = WindowGeometry.zoom(f, factor: 2, about: CGPoint(x: 50, y: 50),
                                    minBound: CGSize(width: 10, height: 10),
                                    maxBound: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(z, CGRect(x: -50, y: -50, width: 200, height: 200))
    }

    func test_zoom_aboutCorner_keepsCornerUnderAnchor() {
        let f = CGRect(x: 0, y: 0, width: 100, height: 100)
        let z = WindowGeometry.zoom(f, factor: 2, about: CGPoint(x: 0, y: 0),
                                    minBound: CGSize(width: 10, height: 10),
                                    maxBound: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(z.minX, 0)
        XCTAssertEqual(z.minY, 0)
    }

    func test_zoom_clampsToMaxBound() {
        let f = CGRect(x: 0, y: 0, width: 100, height: 100)
        let z = WindowGeometry.zoom(f, factor: 10, about: CGPoint(x: 50, y: 50),
                                    minBound: CGSize(width: 10, height: 10),
                                    maxBound: CGSize(width: 150, height: 150))
        XCTAssertEqual(z.width, 150)
        XCTAssertEqual(z.height, 150)
    }
}
