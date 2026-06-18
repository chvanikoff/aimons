import XCTest
@testable import AIMonCore

final class SpeechTests: XCTestCase {
    func test_archetype_isDeterministicFromSeed() {
        XCTAssertEqual(PersonalityGenerator.archetype(seed: 42), PersonalityGenerator.archetype(seed: 42))
    }

    func test_archetype_coversAllCasesAcrossSeeds() {
        let seen = Set((0..<16).map { PersonalityGenerator.archetype(seed: UInt64($0)) })
        XCTAssertEqual(seen, Set(CompanionArchetype.allCases))
    }

    func test_templateLine_nonEmptyForEveryTriggerAndArchetype() {
        let triggers: [SpeechTrigger] = [.sessionStarted, .sessionJoined(count: 2), .sessionLeft(count: 1)]
        for a in CompanionArchetype.allCases {
            for t in triggers {
                XCTAssertFalse(TemplateSpeech.line(trigger: t, archetype: a).isEmpty, "\(a) \(t)")
            }
        }
    }

    func test_templateLine_isDeterministic() {
        XCTAssertEqual(
            TemplateSpeech.line(trigger: .sessionJoined(count: 2), archetype: .grumpy, variant: 2),
            TemplateSpeech.line(trigger: .sessionJoined(count: 2), archetype: .grumpy, variant: 2))
    }

    func test_templateLine_variantRotatesWithinPool() {
        let a = CompanionArchetype.grumpy
        let lines = Set((0..<6).map { TemplateSpeech.line(trigger: .sessionJoined(count: 2), archetype: a, variant: $0) })
        XCTAssertGreaterThan(lines.count, 1, "varying the variant should surface different lines")
    }

    func test_templateLine_negativeVariantIsSafe() {
        XCTAssertFalse(TemplateSpeech.line(trigger: .sessionStarted, archetype: .chill, variant: -3).isEmpty)
    }

    func test_archetypesHaveDistinctVoices() {
        let cheerful = TemplateSpeech.line(trigger: .sessionJoined(count: 2), archetype: .cheerful)
        let grumpy = TemplateSpeech.line(trigger: .sessionJoined(count: 2), archetype: .grumpy)
        XCTAssertNotEqual(cheerful, grumpy)
    }
}
