import XCTest
@testable import AIMonCore

final class MonsterRendererTests: XCTestCase {
    private func render(seed: UInt64) -> PixelImage {
        let traits = TraitGenerator.traits(seed: seed)
        let grid = MonsterGenerator.grid(seed: seed, traits: traits)
        return MonsterRenderer.pixels(grid: grid, traits: traits)
    }

    func test_imageSize_matchesGrid() {
        let img = render(seed: 3)
        XCTAssertEqual(img.width, 7)
        XCTAssertEqual(img.height, 7)
        XCTAssertEqual(img.rgba.count, 7 * 7 * 4)
    }

    func test_emptyCells_areTransparent_filledCells_areOpaque() {
        let traits = TraitGenerator.traits(seed: 4)
        let grid = MonsterGenerator.grid(seed: 4, traits: traits)
        let img = MonsterRenderer.pixels(grid: grid, traits: traits)
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let alpha = img.rgba[(y * grid.width + x) * 4 + 3]
                if grid.at(x, y) {
                    XCTAssertEqual(alpha, 255, "filled cell should be opaque at (\(x),\(y))")
                } else {
                    XCTAssertEqual(alpha, 0, "empty cell should be transparent at (\(x),\(y))")
                }
            }
        }
    }

    func test_hslToRGB_knownValues() {
        // Pure red: hue 0, sat 1, light 0.5
        let red = MonsterRenderer.hslToRGB(h: 0, s: 1, l: 0.5)
        XCTAssertEqual(red.0, 255)
        XCTAssertEqual(red.1, 0)
        XCTAssertEqual(red.2, 0)
    }

    func test_sameSeed_producesIdenticalImage() {
        XCTAssertEqual(render(seed: 8), render(seed: 8))
    }
}
