import Foundation

/// Five personality traits (0–100), derived deterministically from the seed. They flavour speech
/// (rich detail to the LLM, a derived archetype for templates) and, later, animation. Inspired by
/// the trait-vector idea — our own dimensions.
public struct Personality: Codable, Equatable, Sendable {
    public let enthusiasm: Int   // upbeat ↔ flat
    public let patience: Int     // calm ↔ antsy
    public let chaos: Int        // orderly ↔ chaotic
    public let wisdom: Int       // naive ↔ sage
    public let snark: Int        // sweet ↔ sarcastic

    public init(enthusiasm: Int, patience: Int, chaos: Int, wisdom: Int, snark: Int) {
        self.enthusiasm = enthusiasm
        self.patience = patience
        self.chaos = chaos
        self.wisdom = wisdom
        self.snark = snark
    }

    /// A representative personality whose dominant trait matches an archetype (for tests / coarse use).
    public static func representative(of archetype: CompanionArchetype) -> Personality {
        switch archetype {
        case .cheerful: return Personality(enthusiasm: 90, patience: 50, chaos: 40, wisdom: 40, snark: 20)
        case .grumpy:   return Personality(enthusiasm: 30, patience: 40, chaos: 30, wisdom: 50, snark: 90)
        case .chill:    return Personality(enthusiasm: 40, patience: 90, chaos: 20, wisdom: 80, snark: 30)
        case .dramatic: return Personality(enthusiasm: 60, patience: 30, chaos: 90, wisdom: 40, snark: 40)
        }
    }

    /// A coarse archetype derived from the dominant trait — used to pick template lines.
    public var archetype: CompanionArchetype {
        let scored: [(CompanionArchetype, Int)] = [
            (.cheerful, enthusiasm),
            (.grumpy, snark),
            (.dramatic, chaos),
            (.chill, (patience + wisdom) / 2),
        ]
        return scored.max(by: { $0.1 < $1.1 })!.0
    }
}

/// Rarity tiers, gacha-style — rarer is less likely. Drives a badge in the Stable.
public enum Rarity: String, CaseIterable, Codable, Sendable {
    case common, uncommon, rare, epic, legendary, mythic

    public var displayName: String { rawValue.capitalized }

    /// Total personality points distributed across the 5 traits at mint. Rarer creatures get a
    /// bigger pool (more capable overall), but every creature spends a *fixed* budget — so traits
    /// are lean and spiky rather than all near-max. (5 traits × 100 = 500 ceiling.)
    public var traitBudget: Int {
        switch self {
        case .common:    return 150
        case .uncommon:  return 185
        case .rare:      return 220
        case .epic:      return 255
        case .legendary: return 300
        case .mythic:    return 350
        }
    }
}

public enum PersonalityGenerator {
    /// Distribute a rarity's fixed point budget across the five traits, deterministically from the
    /// seed (a stream distinct from the appearance generator's). Rarer creatures get more points to
    /// spend, but the *total* is fixed — so personalities are lean and spiky, and each one is
    /// genuinely distinct rather than all-traits-near-max.
    public static func personality(seed: UInt64, rarity: Rarity) -> Personality {
        var rng = SeededGenerator(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
        let p = distribute(budget: rarity.traitBudget, across: 5, cap: 100, using: &rng)
        return Personality(enthusiasm: p[0], patience: p[1], chaos: p[2], wisdom: p[3], snark: p[4])
    }

    /// Convenience when only the seed is known: uses the seed's canonical (seed-derived) rarity, so
    /// it matches what the registry would mint.
    public static func personality(seed: UInt64) -> Personality {
        personality(seed: seed, rarity: RarityGenerator.rarity(seed: seed))
    }

    /// Convenience: the derived archetype for a seed.
    public static func archetype(seed: UInt64) -> CompanionArchetype {
        personality(seed: seed).archetype
    }

    /// Split `budget` into `n` values each in 0...cap, summing to exactly `budget` (when feasible),
    /// weighted by seeded random affinities so the shape is unique per creature.
    private static func distribute(budget: Int, across n: Int, cap: Int,
                                   using rng: inout SeededGenerator) -> [Int] {
        let target = min(budget, n * cap)
        let weights = (0..<n).map { _ in Double(rng.next() % 1000) + 1 }   // never 0
        let total = weights.reduce(0, +)
        var alloc = weights.map { min(cap, max(0, Int((Double(target) * $0 / total).rounded()))) }

        // Reconcile rounding/clamping to hit the budget exactly, nudging shuffled indices.
        var order = Array(0..<n)
        for i in stride(from: n - 1, to: 0, by: -1) { order.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        var step = 0
        let guardLimit = n * cap * 2
        while alloc.reduce(0, +) != target && step < guardLimit {
            let i = order[step % n]; step += 1
            let diff = target - alloc.reduce(0, +)
            if diff > 0 { if alloc[i] < cap { alloc[i] += 1 } }
            else if alloc[i] > 0 { alloc[i] -= 1 }
        }
        return alloc
    }
}

public enum RarityGenerator {
    // Cumulative weights out of 1000. Tuned so mythic is genuinely special.
    private static let table: [(Rarity, Int)] = [
        (.common, 500), (.uncommon, 800), (.rare, 930), (.epic, 985), (.legendary, 998), (.mythic, 1000),
    ]

    public static func rarity(seed: UInt64) -> Rarity {
        var rng = SeededGenerator(seed: seed ^ 0xD1B5_4A32_D192_ED03)
        let roll = Int(rng.next() % 1000)
        return table.first(where: { roll < $0.1 })!.0
    }
}
