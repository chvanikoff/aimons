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
    case sessionStarted             // the project's monster just appeared (greeting)
    case sessionJoined(count: Int)  // another session opened in this project
    case sessionLeft(count: Int)    // a session closed, project still live
    case idleThought                // an occasional random musing during a quiet stretch
    case activity(SessionActivity)  // a reaction to what the AI is doing right now
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
        case .idleThought:    return idle[archetype]!
        case .activity(let a): return activity(a)
        }
    }

    // Activity floor lines are archetype-agnostic (personality flavor comes from the LLM tier).
    static func activity(_ a: SessionActivity) -> [String] {
        switch a {
        case .editing:  return ["Tinkering with the code, I see.", "Editing away..."]
        case .running:  return ["Running something — let's see.", "Off it goes!"]
        case .testing:  return ["Running the tests — fingers crossed!", "Test time. Moment of truth."]
        case .error:    return ["Uh oh, an error!", "Something broke. Yikes."]
        case .waiting:  return ["Your turn!", "All quiet — over to you."]
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
    private static let idle: [CompanionArchetype: [String]] = [
        .cheerful: ["I wonder what we'll build today!", "I love watching you work.", "Ooh, what does this part do?"],
        .grumpy:   ["Still here. Still watching.", "Don't mind me, just judging the code.", "Are we there yet?"],
        .chill:    ["Just vibing over here.", "Nice and quiet. I like it.", "No rush. Take your time."],
        .dramatic: ["The silence... it's deafening!", "What twists await in this code?", "I sense a great refactor approaching."],
    ]
}

/// Everything needed to compose a spoken line — personality + what just happened.
public struct SpeechContext: Equatable, Sendable {
    public let archetype: CompanionArchetype
    public let trigger: SpeechTrigger
    public let projectName: String
    public let sessionCount: Int

    public init(archetype: CompanionArchetype, trigger: SpeechTrigger, projectName: String, sessionCount: Int) {
        self.archetype = archetype
        self.trigger = trigger
        self.projectName = projectName
        self.sessionCount = sessionCount
    }
}

/// Builds the LLM prompt for a context — in-character, one short line, no emoji, no path leaks.
public enum SpeechPrompt {
    public static func build(for ctx: SpeechContext) -> String {
        """
        You are a tiny pixel-art desktop monster living on a programmer's screen, watching their \
        coding sessions. Your personality: \(persona(ctx.archetype)).
        React to the event below in ONE short, in-character sentence (max 14 words). No emoji. \
        Do not mention file paths or secrets. Reply with only the sentence.
        Event: \(event(ctx.trigger, projectName: ctx.projectName))
        """
    }

    static func persona(_ a: CompanionArchetype) -> String {
        switch a {
        case .cheerful: return "upbeat, warm, and encouraging"
        case .grumpy:   return "grumpy and sarcastic, but secretly caring"
        case .chill:    return "laid-back, calm, and unbothered"
        case .dramatic: return "theatrical and gloriously over-the-top"
        }
    }

    static func event(_ trigger: SpeechTrigger, projectName: String) -> String {
        switch trigger {
        case .sessionStarted:
            return "your human just started a coding session in the project \"\(projectName)\"."
        case .sessionJoined(let count):
            return "your human opened another session in \"\(projectName)\" — there are now \(count) at once."
        case .sessionLeft(let count):
            return "a session in \"\(projectName)\" just closed — \(count) still running."
        case .idleThought:
            return "it's been quiet for a while in \"\(projectName)\"; share a brief, random thought to yourself while you watch."
        case .activity(let a):
            switch a {
            case .editing(let file): return "your human is editing the file \"\(file)\" in \"\(projectName)\"."
            case .running:           return "your human just ran a shell command in \"\(projectName)\"."
            case .testing:           return "your human is running the tests in \"\(projectName)\"."
            case .error:             return "an error just showed up in the output in \"\(projectName)\"."
            case .waiting:           return "the AI finished its turn in \"\(projectName)\" — it's waiting for the human now."
            }
        }
    }
}

/// Pure cadence gate: has enough time passed since the monster last spoke?
public enum SpeechCadence {
    public static func shouldSpeak(lastSpoke: Date?, now: Date, cooldown: TimeInterval) -> Bool {
        guard let last = lastSpoke else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }
}

/// Pure parsing/cleanup of an Ollama `/api/generate` response.
public enum OllamaResponseParser {
    public static func line(fromJSON data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = obj["response"] as? String else { return nil }
        let tidied = tidy(response)
        return tidied.isEmpty ? nil : tidied
    }

    /// Trim, drop wrapping quotes, keep the first non-empty line, cap length at a word boundary.
    public static func tidy(_ raw: String, maxLength: Int = 140) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = s.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            s = String(firstLine).trimmingCharacters(in: .whitespaces)
        }
        if s.count >= 2, s.first == "\"", s.last == "\"" {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        if s.count > maxLength {
            let capped = String(s.prefix(maxLength))
            if let lastSpace = capped.lastIndex(of: " ") {
                s = String(capped[..<lastSpace]) + "…"
            } else {
                s = capped + "…"
            }
        }
        return s
    }
}
