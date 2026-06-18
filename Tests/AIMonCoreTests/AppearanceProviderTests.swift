import XCTest
@testable import AIMonCore

final class AppearanceProviderTests: XCTestCase {
    func test_proceduralAppearance_isDeterministicPerSeed() {
        let provider: AppearanceProvider = ProceduralAppearance()
        XCTAssertEqual(provider.image(for: 77), provider.image(for: 77))
        XCTAssertEqual(provider.traits(for: 77), provider.traits(for: 77))
    }

    func test_proceduralAppearance_imageMatchesManualPipeline() {
        let provider = ProceduralAppearance()
        let traits = TraitGenerator.traits(seed: 21)
        let grid = MonsterGenerator.grid(seed: 21, traits: traits)
        let expected = MonsterRenderer.pixels(grid: grid, traits: traits)
        XCTAssertEqual(provider.image(for: 21), expected)
    }
}
