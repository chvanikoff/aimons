/// An RGBA8 image as plain bytes (row-major, premultiplied-last alpha order R,G,B,A).
public struct PixelImage: Equatable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]   // count == width * height * 4
}

public enum MonsterRenderer {
    public typealias RGB = (UInt8, UInt8, UInt8)

    public static func pixels(grid: MonsterGrid, traits: MonsterTraits) -> PixelImage {
        let w = grid.width
        let h = grid.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)

        let body = hslToRGB(h: traits.hue, s: traits.saturation, l: 0.55)
        let dark = hslToRGB(h: traits.hue, s: traits.saturation, l: 0.38)
        let eye: RGB = traits.eyeIsLight ? (255, 255, 255) : (26, 26, 26)

        func put(_ x: Int, _ y: Int, _ c: RGB) {
            let i = (y * w + x) * 4
            rgba[i] = c.0; rgba[i + 1] = c.1; rgba[i + 2] = c.2; rgba[i + 3] = 255
        }

        for y in 0..<h {
            for x in 0..<w where grid.at(x, y) {
                let isEdge = (y == h - 1 || x == 0 || x == w - 1)
                put(x, y, isEdge ? dark : body)
            }
        }

        // Eyes on row 2, one cell in from each side, only if the body is present there.
        let eyeRow = 2
        let eyeInset = 1
        if eyeRow < h {
            if grid.at(eyeInset, eyeRow) { put(eyeInset, eyeRow, eye) }
            if grid.at(w - 1 - eyeInset, eyeRow) { put(w - 1 - eyeInset, eyeRow, eye) }
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
}
