import XCTest
@testable import AIMonCore

final class IdentityTests: XCTestCase {
    // MARK: - Personality

    func test_personality_isDeterministicAndInRange() {
        let p = PersonalityGenerator.personality(seed: 12345)
        XCTAssertEqual(p, PersonalityGenerator.personality(seed: 12345))
        for v in [p.enthusiasm, p.patience, p.chaos, p.wisdom, p.snark] {
            XCTAssertTrue((0...100).contains(v), "trait \(v) out of range")
        }
    }

    func test_personality_variesAcrossSeeds() {
        let a = PersonalityGenerator.personality(seed: 1)
        let b = PersonalityGenerator.personality(seed: 2)
        XCTAssertNotEqual(a, b)
    }

    func test_personality_spendsExactlyTheRarityBudget() {
        for r in Rarity.allCases {
            let p = PersonalityGenerator.personality(seed: 12345, rarity: r)
            let total = p.enthusiasm + p.patience + p.chaos + p.wisdom + p.snark
            XCTAssertEqual(total, r.traitBudget, "trait total should equal \(r) budget \(r.traitBudget)")
            for v in [p.enthusiasm, p.patience, p.chaos, p.wisdom, p.snark] {
                XCTAssertTrue((0...100).contains(v), "trait \(v) out of range")
            }
        }
    }

    func test_rarerCreaturesHaveMorePoints() {
        func total(_ p: Personality) -> Int { p.enthusiasm + p.patience + p.chaos + p.wisdom + p.snark }
        XCTAssertGreaterThan(total(PersonalityGenerator.personality(seed: 5, rarity: .mythic)),
                             total(PersonalityGenerator.personality(seed: 5, rarity: .common)))
    }

    func test_personality_independentFromAppearanceStream() {
        // Same seed drives appearance traits AND personality, but via different streams — they
        // shouldn't be trivially correlated. Sanity: two seeds with same appearance-ish hue differ.
        XCTAssertNotEqual(PersonalityGenerator.personality(seed: 100),
                          PersonalityGenerator.personality(seed: 101))
    }

    func test_archetype_picksDominantTrait() {
        let snarky = Personality(enthusiasm: 10, patience: 10, chaos: 10, wisdom: 10, snark: 90)
        XCTAssertEqual(snarky.archetype, .grumpy)
        let happy = Personality(enthusiasm: 95, patience: 10, chaos: 10, wisdom: 10, snark: 10)
        XCTAssertEqual(happy.archetype, .cheerful)
        let wild = Personality(enthusiasm: 10, patience: 10, chaos: 95, wisdom: 10, snark: 10)
        XCTAssertEqual(wild.archetype, .dramatic)
        let calm = Personality(enthusiasm: 10, patience: 90, chaos: 10, wisdom: 90, snark: 10)
        XCTAssertEqual(calm.archetype, .chill)
    }

    // MARK: - Rarity

    func test_rarity_isDeterministic() {
        XCTAssertEqual(RarityGenerator.rarity(seed: 777), RarityGenerator.rarity(seed: 777))
    }

    func test_rarity_distributionFavorsCommon() {
        var counts: [Rarity: Int] = [:]
        for s in 0..<3000 { counts[RarityGenerator.rarity(seed: UInt64(s)), default: 0] += 1 }
        XCTAssertGreaterThan(counts[.common, default: 0], counts[.mythic, default: 0],
                             "common should vastly outnumber mythic")
        XCTAssertGreaterThan(counts[.common, default: 0], counts[.legendary, default: 0])
    }

    // MARK: - Names

    func test_name_isDeterministicNonEmptyAndBounded() {
        let n = NameGenerator.name(seed: 42)
        XCTAssertEqual(n, NameGenerator.name(seed: 42))
        XCTAssertFalse(n.isEmpty)
        XCTAssertLessThanOrEqual(n.count, 12)
        XCTAssertTrue(n.first!.isUppercase)
    }

    func test_name_variesAndNoTripledLetters() {
        let names = Set((0..<50).map { NameGenerator.name(seed: UInt64($0)) })
        XCTAssertGreaterThan(names.count, 20, "names should be reasonably diverse")
        for n in names {
            XCTAssertFalse(n.lowercased().contains("aaa") || n.lowercased().contains("ooo"))
        }
    }
}
