import XCTest
@testable import AIMonCore

final class MonsterGridTests: XCTestCase {
    private func makeGrid(seed: UInt64) -> MonsterGrid {
        MonsterGenerator.grid(seed: seed, traits: TraitGenerator.traits(seed: seed))
    }

    func test_dimensions_matchHalfAndHeight() {
        let g = MonsterGenerator.grid(seed: 7,
                                      traits: TraitGenerator.traits(seed: 7),
                                      half: 3, height: 7)
        XCTAssertEqual(g.width, 7)   // half*2 + 1
        XCTAssertEqual(g.height, 7)
        XCTAssertEqual(g.cells.count, 49)
    }

    func test_grid_isHorizontallySymmetric() {
        let g = makeGrid(seed: 9)
        for y in 0..<g.height {
            for x in 0..<g.width {
                XCTAssertEqual(g.at(x, y), g.at(g.width - 1 - x, y),
                               "asymmetry at (\(x),\(y))")
            }
        }
    }

    func test_coreRow_isSolid() {
        let g = makeGrid(seed: 11)
        let core = g.height / 2
        for x in 0..<g.width {
            XCTAssertTrue(g.at(x, core), "core row hole at x=\(x)")
        }
    }

    func test_sameSeed_producesIdenticalGrid() {
        XCTAssertEqual(makeGrid(seed: 5), makeGrid(seed: 5))
    }
}
