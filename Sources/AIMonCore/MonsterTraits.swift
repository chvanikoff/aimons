import Foundation

/// Visual + identity traits for a monster, all derived deterministically from a seed.
public struct MonsterTraits: Equatable {
    public let hue: Double          // 0..<360
    public let saturation: Double   // 0...1
    public let eyeIsLight: Bool
    public let bodyDensity: Double   // 0...1, fill probability for the body grid
    public let name: String
}

public enum TraitGenerator {
    static let syllables = [
        "bo", "zi", "mox", "gru", "fen", "lu", "ka", "wim",
        "vex", "nim", "quo", "rab", "dax", "pip", "zor", "mu",
    ]

    public static func traits(seed: UInt64) -> MonsterTraits {
        var rng = SeededGenerator(seed: seed)
        let hue = Double.random(in: 0..<360, using: &rng)
        let saturation = Double.random(in: 0.55..<0.85, using: &rng)
        let eyeIsLight = Bool.random(using: &rng)
        let bodyDensity = Double.random(in: 0.55..<0.70, using: &rng)
        let partCount = Int.random(in: 2...3, using: &rng)
        var name = ""
        for _ in 0..<partCount {
            name += syllables.randomElement(using: &rng) ?? "mon"
        }
        return MonsterTraits(
            hue: hue,
            saturation: saturation,
            eyeIsLight: eyeIsLight,
            bodyDensity: bodyDensity,
            name: name.capitalized
        )
    }
}
