# Floating Procedural Monster Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `swift run` launches a macOS menu-bar app that displays a transparent, always-on-top, draggable, resizable window containing a procedurally generated pixel-art monster derived deterministically from a seed.

**Architecture:** A pure-Swift core library (`AIMonCore`) generates monster traits and a symmetric pixel grid from a seed and renders it to an RGBA pixel buffer — all unit-tested with no GUI dependency. A thin AppKit/SpriteKit executable (`AIMon`) hosts that buffer as a SpriteKit sprite inside a borderless transparent `NSPanel`. This is the first slice of the design in `docs/superpowers/specs/2026-06-18-aimon-companion-design.md` (Milestones 1–2); it deliberately excludes session tracking, the companion brain, and speech.

**Tech Stack:** Swift 5.9+, Swift Package Manager (executable + library + test targets), AppKit (`NSApplication`, `NSPanel`, `NSStatusItem`), SpriteKit (`SKView`, `SKScene`, `SKSpriteNode`), Core Graphics (`CGImage`). macOS 13+.

**Conventions for the executor:**
- Run `swift build` and `swift test` from the repo root (`/Users/roman/Projects/aimon`).
- TDD applies to all of `AIMonCore` (pure logic). The GUI tasks (executable) cannot be unit-tested headlessly, so they end with an explicit **manual run check** the user performs — these are not skippable.
- Every commit message ends with this trailer (shown in each commit step):
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- Work happens on the current branch `design/aimon-companion`.

---

### Task 1: Package scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/AIMonCore/Version.swift`
- Create: `Tests/AIMonCoreTests/ScaffoldTests.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIMon",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AIMonCore"),
        .testTarget(
            name: "AIMonCoreTests",
            dependencies: ["AIMonCore"]
        ),
    ]
)
```

> Note: the `AIMon` executable target is intentionally **not** declared yet —
> SwiftPM errors if a target has no source files. Task 7 adds it once
> `Sources/AIMon/` exists.

- [ ] **Step 2: Add a placeholder so `AIMonCore` compiles**

`Sources/AIMonCore/Version.swift`:

```swift
public enum AIMonCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 3: Write a scaffold test**

`Tests/AIMonCoreTests/ScaffoldTests.swift`:

```swift
import XCTest
@testable import AIMonCore

final class ScaffoldTests: XCTestCase {
    func test_version_isSet() {
        XCTAssertEqual(AIMonCore.version, "0.1.0")
    }
}
```

- [ ] **Step 4: Run the test**

Run: `swift test`
Expected: PASS (1 test). This proves the package, library target, and test target all build.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/AIMonCore/Version.swift Tests/AIMonCoreTests/ScaffoldTests.swift
git commit -m "$(printf 'chore: scaffold AIMon SwiftPM package\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 2: Deterministic seeded RNG

A reproducible RNG so the same seed always yields the same monster (SplitMix64).

**Files:**
- Create: `Sources/AIMonCore/SeededGenerator.swift`
- Test: `Tests/AIMonCoreTests/SeededGeneratorTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AIMonCoreTests/SeededGeneratorTests.swift`:

```swift
import XCTest
@testable import AIMonCore

final class SeededGeneratorTests: XCTestCase {
    func test_sameSeed_producesSameSequence() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        let seqA = (0..<5).map { _ in a.next() }
        let seqB = (0..<5).map { _ in b.next() }
        XCTAssertEqual(seqA, seqB)
    }

    func test_differentSeeds_produceDifferentSequences() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        let seqA = (0..<5).map { _ in a.next() }
        let seqB = (0..<5).map { _ in b.next() }
        XCTAssertNotEqual(seqA, seqB)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SeededGeneratorTests`
Expected: FAIL — `cannot find 'SeededGenerator' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AIMonCore/SeededGenerator.swift`:

```swift
/// Deterministic SplitMix64 RNG. Same seed -> same sequence, always.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SeededGeneratorTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AIMonCore/SeededGenerator.swift Tests/AIMonCoreTests/SeededGeneratorTests.swift
git commit -m "$(printf 'feat: add deterministic SplitMix64 seeded RNG\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 3: Monster traits from seed

**Files:**
- Create: `Sources/AIMonCore/MonsterTraits.swift`
- Test: `Tests/AIMonCoreTests/MonsterTraitsTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AIMonCoreTests/MonsterTraitsTests.swift`:

```swift
import XCTest
@testable import AIMonCore

final class MonsterTraitsTests: XCTestCase {
    func test_sameSeed_producesIdenticalTraits() {
        let a = TraitGenerator.traits(seed: 123)
        let b = TraitGenerator.traits(seed: 123)
        XCTAssertEqual(a, b)
    }

    func test_hueAndSaturation_inExpectedRanges() {
        for seed in UInt64(0)..<50 {
            let t = TraitGenerator.traits(seed: seed)
            XCTAssertTrue((0..<360).contains(t.hue), "hue out of range: \(t.hue)")
            XCTAssertTrue((0.0...1.0).contains(t.saturation), "sat out of range: \(t.saturation)")
            XCTAssertTrue((0.0...1.0).contains(t.bodyDensity))
            XCTAssertFalse(t.name.isEmpty)
        }
    }

    func test_differentSeeds_usuallyDifferentNames() {
        let names = Set((UInt64(0)..<30).map { TraitGenerator.traits(seed: $0).name })
        XCTAssertGreaterThan(names.count, 10, "names should vary across seeds")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MonsterTraitsTests`
Expected: FAIL — `cannot find 'TraitGenerator' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AIMonCore/MonsterTraits.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MonsterTraitsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AIMonCore/MonsterTraits.swift Tests/AIMonCoreTests/MonsterTraitsTests.swift
git commit -m "$(printf 'feat: derive monster traits deterministically from seed\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 4: Symmetric monster pixel grid

**Files:**
- Create: `Sources/AIMonCore/MonsterGrid.swift`
- Test: `Tests/AIMonCoreTests/MonsterGridTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AIMonCoreTests/MonsterGridTests.swift`:

```swift
import XCTest
@testable import AIMonCore

final class MonsterGridTests: XCTestCase {
    private func makeGrid(seed: UInt64) -> MonsterGrid {
        MonsterGenerator.grid(seed: seed, traits: TraitGenerator.traits(seed: seed))
    }

    func test_dimensions_matchHalfAndHeight() {
        let g = MonsterGenerator.grid(seed: 7,
                                      traits: TraitGenerator.traits(seed: 7),
                                      half: 3, height: 7)
        XCTAssertEqual(g.width, 7)   // half*2 + 1
        XCTAssertEqual(g.height, 7)
        XCTAssertEqual(g.cells.count, 49)
    }

    func test_grid_isHorizontallySymmetric() {
        let g = makeGrid(seed: 9)
        for y in 0..<g.height {
            for x in 0..<g.width {
                XCTAssertEqual(g.at(x, y), g.at(g.width - 1 - x, y),
                               "asymmetry at (\(x),\(y))")
            }
        }
    }

    func test_coreRow_isSolid() {
        let g = makeGrid(seed: 11)
        let core = g.height / 2
        for x in 0..<g.width {
            XCTAssertTrue(g.at(x, core), "core row hole at x=\(x)")
        }
    }

    func test_sameSeed_producesIdenticalGrid() {
        XCTAssertEqual(makeGrid(seed: 5), makeGrid(seed: 5))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MonsterGridTests`
Expected: FAIL — `cannot find 'MonsterGrid' / 'MonsterGenerator' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AIMonCore/MonsterGrid.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MonsterGridTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AIMonCore/MonsterGrid.swift Tests/AIMonCoreTests/MonsterGridTests.swift
git commit -m "$(printf 'feat: generate symmetric monster pixel grid from seed\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 5: Render grid to an RGBA pixel buffer

Pure data output (no AppKit), so it's fully testable. HSL→RGB lives here too.

**Files:**
- Create: `Sources/AIMonCore/MonsterRenderer.swift`
- Test: `Tests/AIMonCoreTests/MonsterRendererTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AIMonCoreTests/MonsterRendererTests.swift`:

```swift
import XCTest
@testable import AIMonCore

final class MonsterRendererTests: XCTestCase {
    private func render(seed: UInt64) -> PixelImage {
        let traits = TraitGenerator.traits(seed: seed)
        let grid = MonsterGenerator.grid(seed: seed, traits: traits)
        return MonsterRenderer.pixels(grid: grid, traits: traits)
    }

    func test_imageSize_matchesGrid() {
        let img = render(seed: 3)
        XCTAssertEqual(img.width, 7)
        XCTAssertEqual(img.height, 7)
        XCTAssertEqual(img.rgba.count, 7 * 7 * 4)
    }

    func test_emptyCells_areTransparent_filledCells_areOpaque() {
        let traits = TraitGenerator.traits(seed: 4)
        let grid = MonsterGenerator.grid(seed: 4, traits: traits)
        let img = MonsterRenderer.pixels(grid: grid, traits: traits)
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let alpha = img.rgba[(y * grid.width + x) * 4 + 3]
                if grid.at(x, y) {
                    XCTAssertEqual(alpha, 255, "filled cell should be opaque at (\(x),\(y))")
                } else {
                    XCTAssertEqual(alpha, 0, "empty cell should be transparent at (\(x),\(y))")
                }
            }
        }
    }

    func test_hslToRGB_knownValues() {
        // Pure red: hue 0, sat 1, light 0.5
        let red = MonsterRenderer.hslToRGB(h: 0, s: 1, l: 0.5)
        XCTAssertEqual(red.0, 255)
        XCTAssertEqual(red.1, 0)
        XCTAssertEqual(red.2, 0)
    }

    func test_sameSeed_producesIdenticalImage() {
        XCTAssertEqual(render(seed: 8), render(seed: 8))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MonsterRendererTests`
Expected: FAIL — `cannot find 'PixelImage' / 'MonsterRenderer' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AIMonCore/MonsterRenderer.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MonsterRendererTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AIMonCore/MonsterRenderer.swift Tests/AIMonCoreTests/MonsterRendererTests.swift
git commit -m "$(printf 'feat: render monster grid to RGBA pixel buffer\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 6: AppearanceProvider protocol + ProceduralAppearance

The swappable seam from the spec (§7.2): consumers depend on a protocol, not the procedural generator.

**Files:**
- Create: `Sources/AIMonCore/AppearanceProvider.swift`
- Test: `Tests/AIMonCoreTests/AppearanceProviderTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AIMonCoreTests/AppearanceProviderTests.swift`:

```swift
import XCTest
@testable import AIMonCore

final class AppearanceProviderTests: XCTestCase {
    func test_proceduralAppearance_isDeterministicPerSeed() {
        let provider: AppearanceProvider = ProceduralAppearance()
        XCTAssertEqual(provider.image(for: 77), provider.image(for: 77))
        XCTAssertEqual(provider.traits(for: 77), provider.traits(for: 77))
    }

    func test_proceduralAppearance_imageMatchesManualPipeline() {
        let provider = ProceduralAppearance()
        let traits = TraitGenerator.traits(seed: 21)
        let grid = MonsterGenerator.grid(seed: 21, traits: traits)
        let expected = MonsterRenderer.pixels(grid: grid, traits: traits)
        XCTAssertEqual(provider.image(for: 21), expected)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppearanceProviderTests`
Expected: FAIL — `cannot find 'AppearanceProvider' / 'ProceduralAppearance' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AIMonCore/AppearanceProvider.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppearanceProviderTests`
Expected: PASS (2 tests). Also run full suite: `swift test` → all green.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIMonCore/AppearanceProvider.swift Tests/AIMonCoreTests/AppearanceProviderTests.swift
git commit -m "$(printf 'feat: add swappable AppearanceProvider with ProceduralAppearance\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 7: Menu-bar app shell (no dock icon)

First executable task. No window yet — just prove the app launches as a menu-bar agent.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AIMon/main.swift`
- Create: `Sources/AIMon/AppDelegate.swift`

- [ ] **Step 0: Add the executable target to `Package.swift`**

Add the executable target to the `targets:` array (between `AIMonCore` and the test target):

```swift
        .executableTarget(
            name: "AIMon",
            dependencies: ["AIMonCore"]
        ),
```

- [ ] **Step 1: Write the app entry point**

`Sources/AIMon/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar agent: no dock icon
app.run()
```

- [ ] **Step 2: Write the AppDelegate with a status item**

`Sources/AIMon/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusItem.button(in: NSStatusBar.system)
        item.button?.title = "👾"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "AIMon (preview)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item
    }
}

private extension NSStatusItem {
    static func button(in bar: NSStatusBar) -> NSStatusItem {
        bar.statusItem(withLength: NSStatusItem.variableLength)
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: MANUAL RUN CHECK (user)**

Run: `swift run AIMon`
Expected: a 👾 icon appears in the macOS menu bar; **no** dock icon appears; clicking the icon shows a menu with "Quit". Quit from the menu (or Ctrl-C in the terminal) to stop.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIMon/main.swift Sources/AIMon/AppDelegate.swift
git commit -m "$(printf 'feat: launch AIMon as a menu-bar agent app\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 8: CGImage bridge + transparent floating window with the monster

Render the procedural monster into a SpriteKit sprite inside a borderless transparent `NSPanel`, drag-to-move enabled.

**Files:**
- Create: `Sources/AIMon/PixelImage+CGImage.swift`
- Create: `Sources/AIMon/CompanionScene.swift`
- Create: `Sources/AIMon/CompanionWindow.swift`
- Modify: `Sources/AIMon/AppDelegate.swift`

- [ ] **Step 1: Bridge `PixelImage` → `CGImage`**

`Sources/AIMon/PixelImage+CGImage.swift`:

```swift
import CoreGraphics
import Foundation
import AIMonCore

extension PixelImage {
    /// Builds a CGImage from the RGBA buffer. Returns nil only on allocation failure.
    func makeCGImage() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
```

- [ ] **Step 2: SpriteKit scene that draws the monster**

`Sources/AIMon/CompanionScene.swift`:

```swift
import SpriteKit
import AIMonCore

/// Renders a single monster sprite, pixel-crisp, centered, on a clear background.
final class CompanionScene: SKScene {
    private let cgImage: CGImage
    private var sprite: SKSpriteNode?

    init(image: PixelImage, size: CGSize) {
        guard let cg = image.makeCGImage() else {
            fatalError("Failed to build CGImage from PixelImage")
        }
        self.cgImage = cg
        super.init(size: size)
        self.scaleMode = .resizeFill
        self.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        let texture = SKTexture(cgImage: cgImage)
        texture.filteringMode = .nearest   // crisp pixels, no blur
        let node = SKSpriteNode(texture: texture)
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        layoutSprite(node, in: size)
        addChild(node)
        self.sprite = node
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard let sprite else { return }
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        layoutSprite(sprite, in: size)
    }

    /// Scales the sprite to fit the scene while preserving aspect ratio and crisp pixels.
    private func layoutSprite(_ node: SKSpriteNode, in container: CGSize) {
        let tex = node.texture!.size()
        let scale = min(container.width / tex.width, container.height / tex.height)
        node.size = CGSize(width: tex.width * scale, height: tex.height * scale)
    }
}
```

- [ ] **Step 3: Borderless transparent floating panel**

`Sources/AIMon/CompanionWindow.swift`:

```swift
import AppKit
import SpriteKit
import AIMonCore

/// A small, borderless, transparent, always-on-top window holding one monster.
final class CompanionWindow: NSPanel {
    private let skView: SKView

    init(seed: UInt64, appearance: AppearanceProvider, pixelScale: CGFloat = 16) {
        let image = appearance.image(for: seed)
        let initial = CGSize(width: CGFloat(image.width) * pixelScale,
                             height: CGFloat(image.height) * pixelScale)

        self.skView = SKView(frame: NSRect(origin: .zero, size: initial))
        skView.allowsTransparency = true

        super.init(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isMovableByWindowBackground = true   // drag the monster to move it
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false

        let scene = CompanionScene(image: image, size: initial)
        skView.presentScene(scene)
        contentView = skView

        // Place it somewhere visible on first launch.
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            setFrameOrigin(NSPoint(x: v.midX - initial.width / 2,
                                   y: v.midY - initial.height / 2))
        }
    }

    override var canBecomeKey: Bool { false }
}
```

- [ ] **Step 4: Show one monster on launch**

Modify `Sources/AIMon/AppDelegate.swift` — add a stored window and create it in `applicationDidFinishLaunching`. The full file becomes:

```swift
import AppKit
import AIMonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var companion: CompanionWindow?
    private let appearance: AppearanceProvider = ProceduralAppearance()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusItem.button(in: NSStatusBar.system)
        item.button?.title = "👾"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "AIMon (preview)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "New random monster",
                                action: #selector(newMonster),
                                keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item

        showMonster(seed: 42)
    }

    @objc private func newMonster() {
        showMonster(seed: UInt64.random(in: 0..<UInt64.max))
    }

    private func showMonster(seed: UInt64) {
        companion?.close()
        let window = CompanionWindow(seed: seed, appearance: appearance)
        window.orderFrontRegardless()
        self.companion = window
    }
}

private extension NSStatusItem {
    static func button(in bar: NSStatusBar) -> NSStatusItem {
        bar.statusItem(withLength: NSStatusItem.variableLength)
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 6: MANUAL RUN CHECK (user)**

Run: `swift run AIMon`
Expected:
- A small floating pixel-art monster appears centered on screen, above other windows, with a transparent background (no window chrome/box).
- Dragging the monster moves it; it stays on top.
- Menu bar → "New random monster" replaces it with a different one each time.
- Quit from the menu.

- [ ] **Step 7: Commit**

```bash
git add Sources/AIMon/PixelImage+CGImage.swift Sources/AIMon/CompanionScene.swift Sources/AIMon/CompanionWindow.swift Sources/AIMon/AppDelegate.swift
git commit -m "$(printf 'feat: show procedural monster in transparent floating window\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 9: Scroll-to-resize the monster

**Files:**
- Create: `Sources/AIMon/CompanionSKView.swift`
- Modify: `Sources/AIMon/CompanionWindow.swift`

- [ ] **Step 1: SKView subclass that reports scroll as a scale delta**

`Sources/AIMon/CompanionSKView.swift`:

```swift
import SpriteKit

/// An SKView that forwards scroll-wheel input as a resize request.
final class CompanionSKView: SKView {
    /// Called with a multiplicative scale factor (>1 grow, <1 shrink).
    var onScaleBy: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let factor = 1.0 + (event.scrollingDeltaY * 0.005)
        let clamped = max(0.9, min(1.1, factor))
        onScaleBy?(clamped)
    }
}
```

- [ ] **Step 2: Replace `CompanionWindow.swift` with the resize-aware version**

Overwrite the entire file `Sources/AIMon/CompanionWindow.swift` with:

```swift
import AppKit
import SpriteKit
import AIMonCore

/// A small, borderless, transparent, always-on-top window holding one monster.
final class CompanionWindow: NSPanel {
    private let skView: CompanionSKView
    private let minSize: CGSize
    private let maxSize: CGSize

    init(seed: UInt64, appearance: AppearanceProvider, pixelScale: CGFloat = 16) {
        let image = appearance.image(for: seed)
        let initial = CGSize(width: CGFloat(image.width) * pixelScale,
                             height: CGFloat(image.height) * pixelScale)
        self.minSize = CGSize(width: initial.width * 0.5, height: initial.height * 0.5)
        self.maxSize = CGSize(width: initial.width * 3.0, height: initial.height * 3.0)

        self.skView = CompanionSKView(frame: NSRect(origin: .zero, size: initial))
        skView.allowsTransparency = true

        super.init(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isMovableByWindowBackground = true   // drag the monster to move it
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false

        skView.onScaleBy = { [weak self] factor in
            self?.scaleBy(factor)
        }

        let scene = CompanionScene(image: image, size: initial)
        skView.presentScene(scene)
        contentView = skView

        // Place it somewhere visible on first launch.
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            setFrameOrigin(NSPoint(x: v.midX - initial.width / 2,
                                   y: v.midY - initial.height / 2))
        }
    }

    override var canBecomeKey: Bool { false }

    private func scaleBy(_ factor: CGFloat) {
        var newW = frame.width * factor
        var newH = frame.height * factor
        newW = max(minSize.width, min(maxSize.width, newW))
        newH = max(minSize.height, min(maxSize.height, newH))
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let newFrame = NSRect(x: center.x - newW / 2, y: center.y - newH / 2,
                              width: newW, height: newH)
        setFrame(newFrame, display: true, animate: false)
        skView.scene?.size = CGSize(width: newW, height: newH)
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: MANUAL RUN CHECK (user)**

Run: `swift run AIMon`
Expected: scrolling (two-finger swipe / mouse wheel) over the monster grows and shrinks it smoothly, staying pixel-crisp and centered, clamped between 0.5× and 3×. Dragging still works; still always-on-top.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIMon/CompanionSKView.swift Sources/AIMon/CompanionWindow.swift
git commit -m "$(printf 'feat: scroll-to-resize the companion monster\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Done criteria

Running `swift run AIMon` shows a procedurally generated, pixel-crisp monster floating over your desktop with no window chrome. You can drag it anywhere, scroll to resize it, and spawn a fresh random one from the menu bar — all on top of a fully unit-tested generation core (`swift test` green). This proves the riskiest pieces (transparent always-on-top overlay + SpriteKit rendering) before any session/brain/speech work.

## Not in this plan (future plans)
- Session Watcher (FSEvents transcript tracking) + spawn/despawn per live Claude Code session.
- AIMon Registry (persistent per-project identity + stable).
- Companion Brain (state machine) + Speech Engine (Ollama/external/template) + bubbles.
- Optional hooks tier, settings UI, onboarding, multi-session hardening.
