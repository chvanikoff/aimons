import XCTest
@testable import AIMonCore

final class MonsterTraitsTests: XCTestCase {
    func test_sameSeed_producesIdenticalTraits() {
        let a = TraitGenerator.traits(seed: 123)
        let b = TraitGenerator.traits(seed: 123)
        XCTAssertEqual(a, b)
    }

    func test_hueAndSaturation_inExpectedRanges() {
        for seed in UInt64(0)..<50 {
            let t = TraitGenerator.traits(seed: seed)
            XCTAssertTrue((0..<360).contains(t.hue), "hue out of range: \(t.hue)")
            XCTAssertTrue((0.0...1.0).contains(t.saturation), "sat out of range: \(t.saturation)")
            XCTAssertTrue((0.0...1.0).contains(t.bodyDensity))
            XCTAssertFalse(t.name.isEmpty)
        }
    }

    func test_differentSeeds_usuallyDifferentNames() {
        let names = Set((UInt64(0)..<30).map { TraitGenerator.traits(seed: $0).name })
        XCTAssertGreaterThan(names.count, 10, "names should vary across seeds")
    }
}
