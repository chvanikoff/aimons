import XCTest
@testable import AIMonCore

final class EvolutionTests: XCTestCase {
    func test_stageThresholds() {
        XCTAssertEqual(Evolution.stage(forXP: 0), 1)
        XCTAssertEqual(Evolution.stage(forXP: 7), 1)
        XCTAssertEqual(Evolution.stage(forXP: 8), 2)
        XCTAssertEqual(Evolution.stage(forXP: 24), 2)
        XCTAssertEqual(Evolution.stage(forXP: 25), 3)
        XCTAssertEqual(Evolution.stage(forXP: 9999), 3, "never exceeds max stage")
    }

    func test_xpToNextStage() {
        XCTAssertEqual(Evolution.xpToNextStage(fromXP: 0), 8)
        XCTAssertEqual(Evolution.xpToNextStage(fromXP: 8), 17)
        XCTAssertNil(Evolution.xpToNextStage(fromXP: 25), "no next stage at max")
    }

    func test_apply_improvesTraits_butKeepsCharacter() {
        let base = Personality(enthusiasm: 40, patience: 40, chaos: 70, wisdom: 30, snark: 80)
        let s1 = Evolution.apply(base, stage: 1)
        XCTAssertEqual(s1, base, "stage 1 is unchanged")

        let s3 = Evolution.apply(base, stage: 3)
        XCTAssertGreaterThan(s3.wisdom, base.wisdom)
        XCTAssertGreaterThan(s3.patience, base.patience)
        XCTAssertGreaterThan(s3.enthusiasm, base.enthusiasm)
        XCTAssertEqual(s3.chaos, base.chaos, "chaos is character, preserved")
        XCTAssertEqual(s3.snark, base.snark, "snark is character, preserved")
    }

    func test_apply_clampsAt100() {
        let base = Personality(enthusiasm: 99, patience: 99, chaos: 50, wisdom: 99, snark: 50)
        let s3 = Evolution.apply(base, stage: 3)
        XCTAssertLessThanOrEqual(s3.wisdom, 100)
        XCTAssertLessThanOrEqual(s3.patience, 100)
        XCTAssertLessThanOrEqual(s3.enthusiasm, 100)
    }

    func test_aimon_stageAndEffectivePersonality() {
        let base = Personality(enthusiasm: 40, patience: 40, chaos: 70, wisdom: 30, snark: 80)
        var a = AIMon(id: UUID(), seed: 1, name: "Test", personality: base, rarity: .common,
                      projectCWD: "/x", createdAt: Date(), lastSeenAt: Date())
        XCTAssertEqual(a.stage, 1)
        XCTAssertEqual(a.effectivePersonality, base)
        a.xp = 30
        XCTAssertEqual(a.stage, 3)
        XCTAssertGreaterThan(a.effectivePersonality.wisdom, base.wisdom)
    }
}
