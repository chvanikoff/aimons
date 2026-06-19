import XCTest
@testable import AIMonCore

final class BehaviorTests: XCTestCase {
    private let chatty = Personality(enthusiasm: 90, patience: 10, chaos: 50, wisdom: 10, snark: 90)
    private let reserved = Personality(enthusiasm: 15, patience: 90, chaos: 10, wisdom: 90, snark: 10)

    func test_chattyTalksMoreOftenThanReserved() {
        let c = BehaviorProfileBuilder.profile(for: chatty)
        let r = BehaviorProfileBuilder.profile(for: reserved)
        XCTAssertLessThan(c.speechCooldown, r.speechCooldown, "chatty has a shorter cooldown")
        XCTAssertLessThan(c.idleMin, r.idleMin, "chatty muses more frequently")
        XCTAssertGreaterThan(c.idleChance, r.idleChance, "chatty more likely to speak when idle")
    }

    func test_livelyMovesMoreThanCalm() {
        let lively = BehaviorProfileBuilder.profile(for: Personality(enthusiasm: 90, patience: 10, chaos: 90, wisdom: 10, snark: 50))
        let calm = BehaviorProfileBuilder.profile(for: Personality(enthusiasm: 10, patience: 90, chaos: 10, wisdom: 70, snark: 20))
        XCTAssertGreaterThan(lively.bobAmplitude, calm.bobAmplitude)
        XCTAssertLessThan(lively.bobDuration, calm.bobDuration, "livelier = faster bob")
    }

    func test_valuesStayInSaneBounds() {
        for p in [chatty, reserved, Personality(enthusiasm: 0, patience: 0, chaos: 0, wisdom: 0, snark: 0),
                  Personality(enthusiasm: 100, patience: 100, chaos: 100, wisdom: 100, snark: 100)] {
            let b = BehaviorProfileBuilder.profile(for: p)
            XCTAssertGreaterThanOrEqual(b.speechCooldown, 2)
            XCTAssertLessThanOrEqual(b.speechCooldown, 13)
            XCTAssertLessThan(b.idleMin, b.idleMax)
            XCTAssertTrue((0...1).contains(b.idleChance))
            XCTAssertGreaterThan(b.bobAmplitude, 0)
            XCTAssertGreaterThan(b.bobDuration, 0)
        }
    }
}
