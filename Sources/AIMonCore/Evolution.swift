import Foundation

/// Evolution: a creature matures through up to three stages as it accrues experience (xp) from
/// being active alongside you. Each stage improves a few traits (it grows wiser, calmer, more
/// spirited) and changes its look (via `AppearanceStyleBuilder`). Chaos and snark are left intact —
/// they're character, not something to "fix".
public enum Evolution {
    public static let maxStage = 3

    /// XP needed to *enter* each stage (index 0 → stage 1, …). Tuned so stage 2 arrives within a
    /// few active sessions and stage 3 is a longer-term milestone.
    public static let thresholds = [0, 8, 25]

    /// The stage for a given xp total (1…maxStage).
    public static func stage(forXP xp: Int) -> Int {
        var s = 1
        for (i, t) in thresholds.enumerated() where xp >= t { s = i + 1 }
        return min(s, maxStage)
    }

    /// XP remaining until the next stage, or nil if already at max.
    public static func xpToNextStage(fromXP xp: Int) -> Int? {
        let s = stage(forXP: xp)
        guard s < maxStage else { return nil }
        return max(0, thresholds[s] - xp)
    }

    /// Fixed point pool an evolution grants per tier (30 points each into the maturity traits:
    /// wisdom +14, patience +10, enthusiasm +6 per stage). Standardised, so evolving is a known,
    /// non-overpowered boost on top of the rarity budget.
    public static let bonusPerStage = 30

    /// Apply maturity to a base personality. Each stage past the first spends `bonusPerStage`
    /// points on wiser/calmer/more-spirited; chaos and snark are preserved (they're character).
    public static func apply(_ base: Personality, stage: Int) -> Personality {
        let steps = max(0, stage - 1)
        func grow(_ v: Int, _ perStep: Int) -> Int { min(100, v + perStep * steps) }
        return Personality(
            enthusiasm: grow(base.enthusiasm, 6),
            patience:   grow(base.patience, 10),
            chaos:      base.chaos,
            wisdom:     grow(base.wisdom, 14),
            snark:      base.snark
        )
    }
}
