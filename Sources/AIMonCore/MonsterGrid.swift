/// A row-major boolean occupancy grid for a monster's body.
public struct MonsterGrid: Equatable {
    public let width: Int
    public let height: Int
    public let cells: [Bool]   // row-major, count == width * height

    public init(width: Int, height: Int, cells: [Bool]) {
        precondition(cells.count == width * height, "cells must be width*height")
        self.width = width
        self.height = height
        self.cells = cells
    }

    public func at(_ x: Int, _ y: Int) -> Bool {
        cells[y * width + x]
    }
}

public enum MonsterGenerator {
    /// Builds a left-half-random, mirrored body grid with a guaranteed solid core row.
    public static func grid(seed: UInt64,
                            traits: MonsterTraits,
                            half: Int = 3,
                            height: Int = 7) -> MonsterGrid {
        // Offset the seed so the grid stream differs from the trait stream.
        var rng = SeededGenerator(seed: seed &+ 0x1)
        let width = half * 2 + 1
        var cells = [Bool](repeating: false, count: width * height)

        func set(_ x: Int, _ y: Int, _ value: Bool) {
            cells[y * width + x] = value
        }

        for y in 0..<height {
            for x in 0...half {
                let probability: Double
                switch y {
                case 0: probability = 0.35
                case height - 1: probability = 0.45
                default: probability = traits.bodyDensity
                }
                let on = Double.random(in: 0..<1, using: &rng) < probability
                set(x, y, on)
                set(width - 1 - x, y, on)
            }
        }

        // Guarantee a solid middle row so no monster is ever disconnected.
        let core = height / 2
        for x in 0..<width { set(x, core, true) }

        return MonsterGrid(width: width, height: height, cells: cells)
    }
}
