/// Swappable appearance seam. Future packs / AI art / 3D implement this without
/// touching the rest of the app.
public protocol AppearanceProvider {
    func traits(for seed: UInt64) -> MonsterTraits
    /// The monster's image at a given rarity and evolution stage, optionally mid-blink.
    func image(for seed: UInt64, rarity: Rarity, stage: Int, eyesClosed: Bool) -> PixelImage
}

public extension AppearanceProvider {
    /// Plain (common, stage-1) image — the default look.
    func image(for seed: UInt64) -> PixelImage {
        image(for: seed, rarity: .common, stage: 1, eyesClosed: false)
    }
    func image(for seed: UInt64, eyesClosed: Bool) -> PixelImage {
        image(for: seed, rarity: .common, stage: 1, eyesClosed: eyesClosed)
    }
    func image(for seed: UInt64, rarity: Rarity, stage: Int) -> PixelImage {
        image(for: seed, rarity: rarity, stage: stage, eyesClosed: false)
    }
}

/// v1 appearance: procedurally generated pixel monster from a seed, with rarity/evolution flair.
public struct ProceduralAppearance: AppearanceProvider {
    public init() {}

    public func traits(for seed: UInt64) -> MonsterTraits {
        TraitGenerator.traits(seed: seed)
    }

    public func image(for seed: UInt64, rarity: Rarity, stage: Int, eyesClosed: Bool) -> PixelImage {
        let t = traits(for: seed)
        let grid = MonsterGenerator.grid(seed: seed, traits: t)
        let style = AppearanceStyleBuilder.style(rarity: rarity, stage: stage)
        return MonsterRenderer.pixels(grid: grid, traits: t, style: style, seed: seed, eyesClosed: eyesClosed)
    }
}
