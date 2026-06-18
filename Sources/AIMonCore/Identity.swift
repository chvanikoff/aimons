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
}

public enum PersonalityGenerator {
    /// Five 0–100 traits from a stream distinct from the appearance generator's (seed is XOR-mixed),
    /// so personality and looks vary independently.
    public static func personality(seed: UInt64) -> Personality {
        var rng = SeededGenerator(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
        func trait() -> Int { Int(rng.next() % 101) }
        return Personality(enthusiasm: trait(), patience: trait(), chaos: trait(), wisdom: trait(), snark: trait())
    }

    /// Convenience: the derived archetype for a seed.
    public static func archetype(seed: UInt64) -> CompanionArchetype {
        personality(seed: seed).archetype
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
