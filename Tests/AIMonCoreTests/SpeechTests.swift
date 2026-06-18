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

    // MARK: - Prompt

    func test_prompt_includesPersonaAndEvent() {
        let ctx = SpeechContext(archetype: .grumpy, trigger: .sessionJoined(count: 2), projectName: "aimon", sessionCount: 2)
        let p = SpeechPrompt.build(for: ctx)
        XCTAssertTrue(p.contains("grumpy"))
        XCTAssertTrue(p.contains("aimon"))
        XCTAssertTrue(p.contains("2"))
        XCTAssertTrue(p.lowercased().contains("no emoji"))
    }

    // MARK: - Cadence

    func test_cadence_allowsWhenNeverSpoken() {
        XCTAssertTrue(SpeechCadence.shouldSpeak(lastSpoke: nil, now: Date(), cooldown: 10))
    }

    func test_cadence_blocksWithinCooldown_allowsAfter() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(SpeechCadence.shouldSpeak(lastSpoke: now.addingTimeInterval(-5), now: now, cooldown: 10))
        XCTAssertTrue(SpeechCadence.shouldSpeak(lastSpoke: now.addingTimeInterval(-15), now: now, cooldown: 10))
    }

    // MARK: - Ollama response parsing

    func test_ollamaParse_extractsResponse() {
        let json = Data(#"{"model":"llama3.2:3b","response":"Two of you now? Let's go!","done":true}"#.utf8)
        XCTAssertEqual(OllamaResponseParser.line(fromJSON: json), "Two of you now? Let's go!")
    }

    func test_ollamaParse_nilOnMissingField() {
        XCTAssertNil(OllamaResponseParser.line(fromJSON: Data(#"{"done":true}"#.utf8)))
        XCTAssertNil(OllamaResponseParser.line(fromJSON: Data("not json".utf8)))
    }

    func test_tidy_stripsQuotesAndExtraLines() {
        XCTAssertEqual(OllamaResponseParser.tidy("  \"Hello there\"\n\nextra "), "Hello there")
    }

    func test_tidy_capsLengthAtWordBoundary() {
        let long = String(repeating: "word ", count: 60)
        let tidied = OllamaResponseParser.tidy(long, maxLength: 40)
        XCTAssertLessThanOrEqual(tidied.count, 41)
        XCTAssertTrue(tidied.hasSuffix("…"))
    }
}
