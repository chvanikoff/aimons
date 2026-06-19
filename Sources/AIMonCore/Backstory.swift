import Foundation

/// A short, deterministic origin story for a creature — a couple of sentences to harden its
/// personality in the Stable. The "nature" line is driven by the creature's *actual* traits (its
/// strongest and weakest), and the quirk is themed to its dominant trait, so the story always makes
/// sense alongside the trait bars. Same inputs always produce the same tale.
public enum BackstoryGenerator {
    public static func backstory(seed: UInt64, name: String, personality: Personality,
                                 rarity: Rarity, projectName: String) -> String {
        var rng = SeededGenerator(seed: seed ^ 0x27D4_EB2F_1656_67C5)
        func pick(_ xs: [String]) -> String { xs[Int(rng.next() % UInt64(xs.count))] }

        let project = projectName.isEmpty ? "an unnamed project" : projectName
        let origin = pick([
            "Hatched from an uncommitted stash deep in \(project).",
            "First compiled into being during a 3 a.m. session on \(project).",
            "Wandered out of a merge conflict in \(project) and decided to stay.",
            "Spawned from a stray TODO nobody ever closed in \(project).",
            "Materialised the day \(project) finally went green.",
            "Booted up from a long-forgotten feature branch of \(project).",
        ])

        // Each trait carries a "high" and a "low" descriptor. The nature line pairs the creature's
        // dominant trait (described high) with its weakest (described low) — so it reads true.
        let traits: [(value: Int, high: String, low: String, key: String)] = [
            (personality.enthusiasm, "bursting with restless energy", "hard to excite", "enthusiasm"),
            (personality.patience,   "unshakeably patient",          "quick to fidget", "patience"),
            (personality.chaos,      "gleefully chaotic",            "tidy and methodical", "chaos"),
            (personality.wisdom,     "wise beyond its versions",     "charmingly naive", "wisdom"),
            (personality.snark,      "razor-tongued",                "sweet-natured", "snark"),
        ]
        let dominant = traits.max { $0.value < $1.value }!
        let weakest = traits.min { $0.value < $1.value }!
        let nature = dominant.key == weakest.key
            ? "\(name) is famously even-keeled."
            : "\(name) is \(dominant.high), though \(weakest.low)."

        let quirk = quirk(forDominant: dominant.key, pick: pick)

        let flourish: String
        switch rarity {
        case .common:    flourish = ""
        case .uncommon:  flourish = "A touch more curious than most of its kind."
        case .rare:      flourish = "Rumoured to bring slightly better luck on deploy day."
        case .epic:      flourish = "Only a handful like it have ever been spotted."
        case .legendary: flourish = "Still whispered about in old commit messages."
        case .mythic:    flourish = "Legend holds that only one will ever exist."
        }

        return [origin, nature, quirk, flourish].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// A quirk themed to the creature's strongest trait, so it reinforces the personality on show.
    private static func quirk(forDominant key: String, pick: ([String]) -> String) -> String {
        switch key {
        case "enthusiasm": return pick(["Cheers out loud whenever the suite goes green.",
                                        "Bounces in place between builds, unable to sit still."])
        case "patience":   return pick(["Will sit perfectly still through a 40-minute CI run.",
                                        "Has never once rushed a code review."])
        case "chaos":      return pick(["Refactors three unrelated things while you debug one.",
                                        "Keeps forty browser tabs open and swears they're all vital."])
        case "wisdom":     return pick(["Quotes commit messages from years ago, verbatim.",
                                        "Always seems to have read the docs already."])
        case "snark":      return pick(["Has opinions about your variable names, and shares them.",
                                        "Rates your git history out of ten, unkindly."])
        default:           return "Keeps a private tally of every rebase."
        }
    }

    /// Convenience for a stored creature: derives project name and uses its matured traits.
    public static func backstory(for aimon: AIMon) -> String {
        let project = (aimon.projectCWD as NSString).lastPathComponent
        return backstory(seed: aimon.seed, name: aimon.name,
                         personality: aimon.effectivePersonality,
                         rarity: aimon.rarity, projectName: project)
    }
}
