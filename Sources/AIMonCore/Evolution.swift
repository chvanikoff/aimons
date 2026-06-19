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

    /// Apply maturity to a base personality. Each stage past the first nudges the creature toward
    /// wiser/calmer/more-spirited; chaos and snark are preserved.
    public static func apply(_ base: Personality, stage: Int) -> Personality {
        let steps = max(0, stage - 1)
        func grow(_ v: Int, _ perStep: Int) -> Int { min(100, v + perStep * steps) }
        return Personality(
            enthusiasm: grow(base.enthusiasm, 6),
            patience:   grow(base.patience, 8),
            chaos:      base.chaos,
            wisdom:     grow(base.wisdom, 12),
            snark:      base.snark
        )
    }
}
