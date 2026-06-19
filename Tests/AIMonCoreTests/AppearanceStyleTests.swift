import XCTest
@testable import AIMonCore

final class AppearanceStyleTests: XCTestCase {
    private func render(seed: UInt64, rarity: Rarity, stage: Int) -> PixelImage {
        let t = TraitGenerator.traits(seed: seed)
        let grid = MonsterGenerator.grid(seed: seed, traits: t)
        let style = AppearanceStyleBuilder.style(rarity: rarity, stage: stage)
        return MonsterRenderer.pixels(grid: grid, traits: t, style: style, seed: seed)
    }

    func test_baseStyle_isNoOp_matchesOriginalPipeline() {
        // A common, stage-1 creature must render byte-identically to the plain renderer.
        let t = TraitGenerator.traits(seed: 42)
        let grid = MonsterGenerator.grid(seed: 42, traits: t)
        let plain = MonsterRenderer.pixels(grid: grid, traits: t)
        let common = render(seed: 42, rarity: .common, stage: 1)
        XCTAssertEqual(plain, common)
    }

    func test_rarity_changesAppearance() {
        XCTAssertNotEqual(render(seed: 42, rarity: .common, stage: 1),
                          render(seed: 42, rarity: .mythic, stage: 1),
                          "mythic should look different from common")
    }

    func test_evolution_changesAppearance() {
        XCTAssertNotEqual(render(seed: 7, rarity: .common, stage: 1),
                          render(seed: 7, rarity: .common, stage: 3),
                          "an evolved creature should look different")
    }

    func test_decoration_isDeterministic() {
        XCTAssertEqual(render(seed: 99, rarity: .epic, stage: 2),
                       render(seed: 99, rarity: .epic, stage: 2))
    }

    func test_styleBuilder_scalesWithRarity() {
        let common = AppearanceStyleBuilder.style(rarity: .common, stage: 1)
        let mythic = AppearanceStyleBuilder.style(rarity: .mythic, stage: 1)
        XCTAssertEqual(common, .base)
        XCTAssertGreaterThan(mythic.accentSpots, common.accentSpots)
        XCTAssertTrue(mythic.shimmerRim)
    }

    func test_styleBuilder_stageAddsFeatures() {
        let s1 = AppearanceStyleBuilder.style(rarity: .common, stage: 1)
        let s2 = AppearanceStyleBuilder.style(rarity: .common, stage: 2)
        let s3 = AppearanceStyleBuilder.style(rarity: .common, stage: 3)
        XCTAssertFalse(s1.horns)
        XCTAssertTrue(s2.horns)
        XCTAssertTrue(s3.gem)
        XCTAssertGreaterThan(s3.brightnessBoost, s1.brightnessBoost)
    }
}
