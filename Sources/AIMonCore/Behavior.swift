import Foundation

/// How a creature *behaves*, derived from its personality — not just what it says, but how often it
/// pipes up and how lively it looks. So a snarky, impatient, enthusiastic creature chatters and
/// bounces, while a patient, wise one is calm and speaks rarely (but, one assumes, meaningfully).
public struct BehaviorProfile: Equatable, Sendable {
    public let speechCooldown: TimeInterval   // minimum seconds between any two lines
    public let idleMin: Int                   // lower bound (seconds) of the gap between idle musings
    public let idleMax: Int                   // upper bound
    public let idleChance: Double             // 0…1: chance it actually speaks when an idle window is due
    public let bobAmplitude: Double           // idle bob height
    public let bobDuration: Double            // seconds per bob half-cycle (smaller = livelier)
    public let talkativeness: Double          // 0…1, for reference
    public let liveliness: Double             // 0…1, for reference / reaction scaling

    public init(speechCooldown: TimeInterval, idleMin: Int, idleMax: Int, idleChance: Double,
                bobAmplitude: Double, bobDuration: Double, talkativeness: Double, liveliness: Double) {
        self.speechCooldown = speechCooldown; self.idleMin = idleMin; self.idleMax = idleMax
        self.idleChance = idleChance; self.bobAmplitude = bobAmplitude; self.bobDuration = bobDuration
        self.talkativeness = talkativeness; self.liveliness = liveliness
    }
}

public enum BehaviorProfileBuilder {
    public static func profile(for p: Personality) -> BehaviorProfile {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

        // Talkativeness: the enthusiastic, snarky and impatient chatter; the wise hold their tongue.
        let chat = Double(p.enthusiasm) * 0.40 + Double(p.snark) * 0.35
                 + Double(100 - p.patience) * 0.25 - Double(p.wisdom) * 0.15
        let talk = clamp(chat / 100, 0, 1)

        // Liveliness: energy + chaos make for bigger, faster motion.
        let live = clamp((Double(p.enthusiasm) * 0.6 + Double(p.chaos) * 0.4) / 100, 0, 1)

        let idleCenter = 480 - talk * 300                  // chatty ≈180s … reserved ≈480s
        return BehaviorProfile(
            speechCooldown: 12 - talk * 9,                 // chatty ≈3s … reserved ≈12s
            idleMin: Int(idleCenter),
            idleMax: Int(idleCenter) + 240,
            idleChance: 0.40 + talk * 0.60,                // reserved 0.40 … chatty 1.0
            bobAmplitude: 2 + live * 5,                    // calm 2 … lively 7
            bobDuration: 1.4 - live * 0.8,                 // calm 1.4s … lively 0.6s
            talkativeness: talk,
            liveliness: live
        )
    }
}
