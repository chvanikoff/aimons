import Foundation

/// A short, deterministic origin story for a creature — a couple of sentences to harden its
/// personality in the Stable's detail view. Same inputs always produce the same tale.
public enum BackstoryGenerator {
    public static func backstory(seed: UInt64, name: String, archetype: CompanionArchetype,
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

        let nature: String
        switch archetype {
        case .cheerful: nature = "Relentlessly upbeat, \(name) cheers for every passing test."
        case .grumpy:   nature = "\(name) has strong opinions about your variable names — and shares them."
        case .chill:    nature = "Nothing rattles \(name), not even a red build on a Friday afternoon."
        case .dramatic: nature = "\(name) treats every off-by-one error like a season finale."
        }

        let quirk = pick([
            "Collects rare semicolons.",
            "Naps in a corner of the screen between builds.",
            "Insists it has read the entire changelog.",
            "Hums quietly whenever the suite goes green.",
            "Distrusts any function longer than the screen.",
            "Keeps a private tally of every rebase.",
            "Believes the bug is always in the last place you look, so it looks there first.",
        ])

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

    /// Convenience for a stored creature: derives project name and uses its matured archetype.
    public static func backstory(for aimon: AIMon) -> String {
        let project = (aimon.projectCWD as NSString).lastPathComponent
        return backstory(seed: aimon.seed, name: aimon.name,
                         archetype: aimon.effectivePersonality.archetype,
                         rarity: aimon.rarity, projectName: project)
    }
}
