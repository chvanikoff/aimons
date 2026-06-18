/// Swappable appearance seam. Future packs / AI art / 3D implement this without
/// touching the rest of the app.
public protocol AppearanceProvider {
    func traits(for seed: UInt64) -> MonsterTraits
    func image(for seed: UInt64) -> PixelImage
    /// Variant with eyes closed, for the blink animation frame.
    func image(for seed: UInt64, eyesClosed: Bool) -> PixelImage
}

public extension AppearanceProvider {
    func image(for seed: UInt64) -> PixelImage { image(for: seed, eyesClosed: false) }
}

/// v1 appearance: procedurally generated pixel monster from a seed.
public struct ProceduralAppearance: AppearanceProvider {
    public init() {}

    public func traits(for seed: UInt64) -> MonsterTraits {
        TraitGenerator.traits(seed: seed)
    }

    public func image(for seed: UInt64, eyesClosed: Bool) -> PixelImage {
        let t = traits(for: seed)
        let grid = MonsterGenerator.grid(seed: seed, traits: t)
        return MonsterRenderer.pixels(grid: grid, traits: t, eyesClosed: eyesClosed)
    }
}
