import Foundation

/// A monster's broad personality, derived deterministically from its seed. Flavors template
/// selection now, and (in the LLM tier) the speech prompt.
public enum CompanionArchetype: String, CaseIterable, Sendable {
    case cheerful, grumpy, chill, dramatic
}

public enum PersonalityGenerator {
    public static func archetype(seed: UInt64) -> CompanionArchetype {
        let all = CompanionArchetype.allCases
        return all[Int(seed % UInt64(all.count))]
    }
}

/// Why the monster is speaking — derived from session lifecycle (richer transcript-activity
/// triggers come later, once the per-session activity reader exists).
public enum SpeechTrigger: Equatable, Sendable {
    case sessionStarted             // the project's monster just appeared
    case sessionJoined(count: Int)  // another session opened in this project
    case sessionLeft(count: Int)    // a session closed, project still live
}

/// Offline template lines — the always-available speech floor, keyed by (trigger, archetype).
/// `variant` rotates the choice (callers pass the session count or a nonce for variety).
public enum TemplateSpeech {
    public static func line(trigger: SpeechTrigger, archetype: CompanionArchetype, variant: Int = 0) -> String {
        let pool = pool(trigger: trigger, archetype: archetype)
        let idx = ((variant % pool.count) + pool.count) % pool.count   // safe modulo for any Int
        return pool[idx]
    }

    static func pool(trigger: SpeechTrigger, archetype: CompanionArchetype) -> [String] {
        switch trigger {
        case .sessionStarted: return started[archetype]!
        case .sessionJoined:  return joined[archetype]!
        case .sessionLeft:    return left[archetype]!
        }
    }

    private static let started: [CompanionArchetype: [String]] = [
        .cheerful: ["Ready to build something great!", "Oh hi! Let's make something."],
        .grumpy:   ["Back to work, I suppose.", "Fine. What are we breaking today?"],
        .chill:    ["Hey. Let's take it easy.", "Cool, we're coding. No rush."],
        .dramatic: ["The session BEGINS!", "Destiny calls — to the keyboard!"],
    ]
    private static let joined: [CompanionArchetype: [String]] = [
        .cheerful: ["Ooh, a second session! Double the fun!", "More of you? Amazing!", "Another session — let's go!"],
        .grumpy:   ["Great. MORE work.", "Another one? Wonderful.", "Two sessions now? Ugh."],
        .chill:    ["Oh, another session joined. Neat.", "Two of us watching now. Chill.", "More sessions, same vibe."],
        .dramatic: ["A new session enters the arena!", "Two fronts now — how thrilling!", "The plot thickens!"],
    ]
    private static let left: [CompanionArchetype: [String]] = [
        .cheerful: ["One down, still going strong!", "Back to it — we got this!"],
        .grumpy:   ["Finally, one less to track.", "Good riddance."],
        .chill:    ["And then there was one. All good.", "A session wandered off. Whatever."],
        .dramatic: ["One falls! The quest continues!", "A session departs into the void..."],
    ]
}
