/// Swappable appearance seam. Future packs / AI art / 3D implement this without
/// touching the rest of the app.
public protocol AppearanceProvider {
    func traits(for seed: UInt64) -> MonsterTraits
    func image(for seed: UInt64) -> PixelImage
}

/// v1 appearance: procedurally generated pixel monster from a seed.
public struct ProceduralAppearance: AppearanceProvider {
    public init() {}

    public func traits(for seed: UInt64) -> MonsterTraits {
        TraitGenerator.traits(seed: seed)
    }

    public func image(for seed: UInt64) -> PixelImage {
        let t = traits(for: seed)
        let grid = MonsterGenerator.grid(seed: seed, traits: t)
        return MonsterRenderer.pixels(grid: grid, traits: t)
    }
}
