import Foundation

/// Deterministic seed → monster name. Combines original, Pokémon-flavoured morphemes (punchy,
/// pronounceable) — inspired by the genre, not copied; the pools deliberately avoid real names.
public enum NameGenerator {
    public static func name(seed: UInt64) -> String {
        var rng = SeededGenerator(seed: seed ^ 0xA076_1D64_78BD_642F)
        let prefix = prefixes[Int(rng.next() % UInt64(prefixes.count))]
        let middle = (rng.next() % 2 == 0) ? middles[Int(rng.next() % UInt64(middles.count))] : ""
        let suffix = suffixes[Int(rng.next() % UInt64(suffixes.count))]
        return cleanup(prefix + middle + suffix)
    }

    private static func cleanup(_ raw: String) -> String {
        // collapse 3+ repeated letters, cap length, Capitalize first letter only
        var out = ""
        var run: Character = " "
        var runLen = 0
        for ch in raw.lowercased() {
            if ch == run { runLen += 1 } else { run = ch; runLen = 1 }
            if runLen <= 2 { out.append(ch) }
        }
        if out.count > 12 { out = String(out.prefix(12)) }
        guard let first = out.first else { return "Aimon" }
        return first.uppercased() + out.dropFirst()
    }

    private static let prefixes = [
        "zor", "bla", "mor", "pyr", "glim", "vex", "quil", "nim", "drae", "fen",
        "lum", "squi", "gren", "mag", "tox", "zub", "aer", "wisp", "bryn", "cob",
        "dru", "eko", "fizz", "grok", "hex", "kael", "myr", "noc", "orb", "plox",
        "rune", "syl", "thal", "umb", "vorn", "wex", "ylx", "zeph", "krill", "snor",
    ]
    private static let middles = ["a", "o", "i", "ar", "ol", "im", "en", "ux", "yl", "ae"]
    private static let suffixes = [
        "mon", "zar", "eon", "puff", "saur", "ling", "dot", "ix", "oth", "quat",
        "izzle", "omp", "ynx", "ax", "oo", "ette", "gore", "wing", "fang", "bloom",
    ]
}
