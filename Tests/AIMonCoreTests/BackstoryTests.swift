import XCTest
@testable import AIMonCore

final class BackstoryTests: XCTestCase {
    func test_isDeterministic() {
        let a = BackstoryGenerator.backstory(seed: 5, name: "Quileneon", archetype: .cheerful,
                                             rarity: .rare, projectName: "aimon")
        let b = BackstoryGenerator.backstory(seed: 5, name: "Quileneon", archetype: .cheerful,
                                             rarity: .rare, projectName: "aimon")
        XCTAssertEqual(a, b)
    }

    func test_mentionsNameAndProject() {
        let s = BackstoryGenerator.backstory(seed: 5, name: "Quileneon", archetype: .grumpy,
                                             rarity: .epic, projectName: "aimon")
        XCTAssertTrue(s.contains("Quileneon"))
        XCTAssertTrue(s.contains("aimon"))
        XCTAssertFalse(s.isEmpty)
    }

    func test_rarityAddsFlourish() {
        let common = BackstoryGenerator.backstory(seed: 9, name: "X", archetype: .chill,
                                                  rarity: .common, projectName: "p")
        let mythic = BackstoryGenerator.backstory(seed: 9, name: "X", archetype: .chill,
                                                  rarity: .mythic, projectName: "p")
        XCTAssertGreaterThan(mythic.count, common.count, "rarer creatures get an extra flourish")
    }

    func test_convenienceFromAIMon() {
        let a = AIMon(id: UUID(), seed: 3, name: "Vornquat",
                      personality: PersonalityGenerator.personality(seed: 3), rarity: .legendary,
                      projectCWD: "/Users/roman/Projects/aimon", createdAt: Date(), lastSeenAt: Date())
        XCTAssertTrue(BackstoryGenerator.backstory(for: a).contains("Vornquat"))
    }
}
