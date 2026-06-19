import Foundation

/// An RGBA8 image as plain bytes (row-major, premultiplied-last alpha order R,G,B,A).
public struct PixelImage: Equatable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]   // count == width * height * 4
}

public enum MonsterRenderer {
    public typealias RGB = (UInt8, UInt8, UInt8)

    /// Render the monster. `style` layers rarity/evolution flair on top; `seed` makes the
    /// decoration (accent-spot placement) deterministic. With `style == .base` the output is
    /// byte-identical to the original common/unevolved pipeline (decorations are no-ops).
    public static func pixels(grid: MonsterGrid, traits: MonsterTraits,
                              style: AppearanceStyle = .base, seed: UInt64 = 0,
                              eyesClosed: Bool = false) -> PixelImage {
        let w = grid.width
        let h = grid.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)

        let hue = (traits.hue + style.hueShift).truncatingRemainder(dividingBy: 360)
        let sat = clamp(traits.saturation + style.saturationBoost, 0, 1)
        let bb = style.brightnessBoost

        let body  = hslToRGB(h: hue, s: sat, l: clamp(0.55 + bb, 0, 0.9))
        let dark  = hslToRGB(h: hue, s: sat, l: clamp(0.36 + bb * 0.5, 0, 0.9))   // edge / shading
        let light = hslToRGB(h: hue, s: sat, l: clamp(0.72 + bb, 0, 0.95))        // lit-from-above highlight
        let rim   = hslToRGB(h: hue, s: clamp(sat + 0.1, 0, 1), l: clamp(0.84 + bb * 0.3, 0, 0.97))
        let accent = hslToRGB(h: (hue + 155).truncatingRemainder(dividingBy: 360),
                              s: clamp(sat + 0.15, 0, 1), l: clamp(0.60 + bb, 0, 0.9))
        let gemColor = hslToRGB(h: (hue + 155).truncatingRemainder(dividingBy: 360),
                                s: 1, l: clamp(0.86 + bb * 0.2, 0, 0.97))
        let eye: RGB = traits.eyeIsLight ? (245, 245, 245) : (28, 28, 28)

        func put(_ x: Int, _ y: Int, _ c: RGB) {
            guard x >= 0, x < w, y >= 0, y < h else { return }
            let i = (y * w + x) * 4
            rgba[i] = c.0; rgba[i + 1] = c.1; rgba[i + 2] = c.2; rgba[i + 3] = 255
        }

        // Topmost filled cell per column → highlight, for a subtle sense of volume.
        var topY = [Int](repeating: -1, count: w)
        for x in 0..<w {
            for y in 0..<h where grid.at(x, y) { topY[x] = y; break }
        }

        let eyeRow = 2
        let eyeInset = 1

        for y in 0..<h {
            for x in 0..<w where grid.at(x, y) {
                let isEdge = (y == h - 1 || x == 0 || x == w - 1)
                if isEdge { put(x, y, style.shimmerRim ? rim : dark) }
                else if y == topY[x] { put(x, y, light) }
                else { put(x, y, body) }
            }
        }

        // Accent spots: recolour a few interior cells (mirrored for symmetry) with a complementary
        // pop. Placement is seeded so it's stable per creature.
        if style.accentSpots > 0 {
            let half = (w - 1) / 2
            var candidates: [(Int, Int)] = []
            for x in 1...half {
                for y in 1..<(h - 1) where grid.at(x, y) && !(x == eyeInset && y == eyeRow) {
                    candidates.append((x, y))
                }
            }
            var rng = SeededGenerator(seed: seed ^ 0x5BD1_E995_2F1B_AED3)
            shuffle(&candidates, using: &rng)
            for (x, y) in candidates.prefix(style.accentSpots) {
                put(x, y, accent)
                put(w - 1 - x, y, accent)
            }
        }

        // Horns: top-corner cells sprout as the creature matures (drawn even on empty cells).
        if style.horns {
            put(1, 0, style.shimmerRim ? rim : dark)
            put(w - 2, 0, style.shimmerRim ? rim : dark)
        }

        // Gem: a bright sparkle at the always-filled core, for the final stage.
        if style.gem {
            put(w / 2, h / 2, gemColor)
        }

        // Eyes last, so nothing covers them. Closed eyes use the dark shade (a sleepy dash).
        let eyeColor = eyesClosed ? dark : eye
        if eyeRow < h {
            if grid.at(eyeInset, eyeRow) { put(eyeInset, eyeRow, eyeColor) }
            if grid.at(w - 1 - eyeInset, eyeRow) { put(w - 1 - eyeInset, eyeRow, eyeColor) }
        }

        return PixelImage(width: w, height: h, rgba: rgba)
    }

    /// h in [0,360), s and l in [0,1]. Returns 8-bit RGB.
    public static func hslToRGB(h: Double, s: Double, l: Double) -> RGB {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h / 60.0
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var r = 0.0, g = 0.0, b = 0.0
        switch hp {
        case 0..<1: (r, g, b) = (c, x, 0)
        case 1..<2: (r, g, b) = (x, c, 0)
        case 2..<3: (r, g, b) = (0, c, x)
        case 3..<4: (r, g, b) = (0, x, c)
        case 4..<5: (r, g, b) = (x, 0, c)
        default:    (r, g, b) = (c, 0, x)
        }
        let m = l - c / 2
        func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v + m) * 255 + 0.5))) }
        return (byte(r), byte(g), byte(b))
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    private static func shuffle<T>(_ a: inout [T], using rng: inout SeededGenerator) {
        guard a.count > 1 else { return }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            a.swapAt(i, j)
        }
    }
}
