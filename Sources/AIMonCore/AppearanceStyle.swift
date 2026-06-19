import Foundation

/// Visual embellishments layered on top of a monster's base procedural look. Driven by *rarity*
/// (how special the creature is) and *evolution stage* (how mature it is). The base style is a
/// no-op, so a common, stage-1 creature renders exactly as the original pipeline did.
public struct AppearanceStyle: Equatable, Sendable {
    public var brightnessBoost: Double   // added to body/edge/highlight lightness
    public var saturationBoost: Double   // added to saturation (more vivid)
    public var hueShift: Double          // degrees added to the base hue (evolution drift)
    public var accentSpots: Int          // recoloured interior cells (mirrored), a complementary pop
    public var shimmerRim: Bool          // bright outline instead of the dark edge (legendary+)
    public var horns: Bool               // top-corner cells sprout (evolution stage ≥ 2)
    public var gem: Bool                 // bright core sparkle (evolution stage 3)

    public init(brightnessBoost: Double = 0, saturationBoost: Double = 0, hueShift: Double = 0,
                accentSpots: Int = 0, shimmerRim: Bool = false, horns: Bool = false, gem: Bool = false) {
        self.brightnessBoost = brightnessBoost
        self.saturationBoost = saturationBoost
        self.hueShift = hueShift
        self.accentSpots = accentSpots
        self.shimmerRim = shimmerRim
        self.horns = horns
        self.gem = gem
    }

    /// A no-op style: renders identically to the original (common, unevolved) pipeline.
    public static let base = AppearanceStyle()
}

public enum AppearanceStyleBuilder {
    /// Combine rarity flair and evolution maturity into one render style.
    public static func style(rarity: Rarity, stage: Int) -> AppearanceStyle {
        var s = AppearanceStyle.base

        switch rarity {
        case .common:
            break
        case .uncommon:
            s.accentSpots = 1; s.saturationBoost = 0.03; s.brightnessBoost = 0.02
        case .rare:
            s.accentSpots = 2; s.saturationBoost = 0.06; s.brightnessBoost = 0.03
        case .epic:
            s.accentSpots = 3; s.saturationBoost = 0.09; s.brightnessBoost = 0.04
        case .legendary:
            s.accentSpots = 4; s.saturationBoost = 0.11; s.brightnessBoost = 0.05; s.shimmerRim = true
        case .mythic:
            s.accentSpots = 6; s.saturationBoost = 0.14; s.brightnessBoost = 0.07; s.shimmerRim = true
        }

        // Evolution maturity stacks on top: a fuller, brighter, hue-drifted look with new features.
        if stage >= 2 {
            s.horns = true
            s.brightnessBoost += 0.03; s.saturationBoost += 0.03; s.accentSpots += 1; s.hueShift += 8
        }
        if stage >= 3 {
            s.gem = true; s.shimmerRim = true
            s.brightnessBoost += 0.03; s.saturationBoost += 0.03; s.accentSpots += 1; s.hueShift += 8
        }
        return s
    }
}
