import AppKit
import SwiftUI
import AIMonCore

// Hidden dev mode: `AIMon --speech-test` exercises the real Ollama speech path once and exits,
// so the LLM tier can be verified headlessly (no GUI / window needed).
if CommandLine.arguments.contains("--speech-test") {
    let ctx = SpeechContext(archetype: .grumpy, trigger: .sessionJoined(count: 2),
                            projectName: "aimon", sessionCount: 2)
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let line = try await OllamaProvider().line(for: ctx)
            print("OLLAMA OK: \(line)")
        } catch {
            print("OLLAMA FAIL (falls back to template): \(error)")
            print("template floor: \(TemplateSpeech.line(trigger: ctx.trigger, archetype: ctx.archetype, variant: ctx.sessionCount))")
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

// Hidden dev mode: `AIMon --identity-test` prints sample identities so name/rarity/trait quality
// can be eyeballed without the GUI.
if CommandLine.arguments.contains("--identity-test") {
    let sampleCWDs = [
        "/Users/roman/Projects/aimon", "/Users/roman/Projects/web", "/Users/roman/work/api",
        "/tmp/scratch", "/Users/roman/Projects/game-engine", "/Users/roman/dotfiles",
        "/Users/roman/Projects/ml-thing", "/Users/roman/sideproject", "/Users/roman/Projects/cli-tool",
        "/Users/roman/Projects/aimon-test", "/Users/roman/Projects/zeta", "/Users/roman/Projects/omega",
    ]
    for cwd in sampleCWDs {
        let seed = ProjectIdentity.seed(forCWD: cwd)
        let p = PersonalityGenerator.personality(seed: seed)
        let name = NameGenerator.name(seed: seed)
        let rarity = RarityGenerator.rarity(seed: seed)
        print(String(format: "%-12@ %-10@ [%@] enth:%-3d pat:%-3d chaos:%-3d wis:%-3d snark:%-3d  (%@)",
                     name as NSString, rarity.displayName as NSString, p.archetype.rawValue as NSString,
                     p.enthusiasm, p.patience, p.chaos, p.wisdom, p.snark, (cwd as NSString).lastPathComponent as NSString))
    }
    exit(0)
}

// Hidden dev mode: `AIMon --render-test` writes a contact sheet of generated monsters to
// /tmp/aimon-render/sheet.png so the procedural graphics can be eyeballed without the GUI.
if CommandLine.arguments.contains("--render-test") {
    func scaledCGImage(_ img: PixelImage, scale: Int) -> CGImage? {
        guard let cg = img.makeCGImage() else { return nil }
        let w = img.width * scale, h = img.height * scale
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    let appearance = ProceduralAppearance()
    // Matrix: each row a different creature; columns show the rarity ladder at stage 1, then the
    // same creature evolving (mythic s2, s3). Lets rarity (#5) and evolution (#6) be eyeballed.
    let seeds: [UInt64] = [3, 21, 42, 99, 128, 777].map { ProjectIdentity.seed(forCWD: "/s/\($0)") }
    let rarities: [Rarity] = [.common, .uncommon, .rare, .epic, .legendary, .mythic]
    let scale = 14, pad = 14
    let cols = rarities.count + 2   // + mythic stage 2 and stage 3
    var images: [PixelImage] = []
    for s in seeds {
        for r in rarities { images.append(appearance.image(for: s, rarity: r, stage: 1)) }
        images.append(appearance.image(for: s, rarity: .mythic, stage: 2))
        images.append(appearance.image(for: s, rarity: .mythic, stage: 3))
    }
    let cell = 7 * scale + pad
    let rows = (images.count + cols - 1) / cols
    let sheetW = cols * cell + pad, sheetH = rows * cell + pad
    let ctx = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
    ctx.interpolationQuality = .none
    for (i, img) in images.enumerated() {
        guard let cg = scaledCGImage(img, scale: scale) else { continue }
        let col = i % cols, row = i / cols
        ctx.draw(cg, in: CGRect(x: col * cell + pad, y: sheetH - (row + 1) * cell, width: 7 * scale, height: 7 * scale))
    }
    let dir = "/tmp/aimon-render"; try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if let sheet = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: sheet).representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(dir)/sheet.png"))
        print("wrote \(dir)/sheet.png")
    }
    exit(0)
}

// Hidden dev mode: `AIMon --stable-test` renders the Stable cards (one per rarity, varied stages)
// and a detail view to PNGs for eyeballing the rarity styling (#7) and detail/backstory (#8).
if CommandLine.arguments.contains("--stable-test") {
    let appearance = ProceduralAppearance()
    let created = Date(timeIntervalSince1970: 1_700_000_000)
    // One creature per rarity, with escalating xp so stage (and its look) also varies.
    let entries = Rarity.allCases.enumerated().map { i, rarity -> StableEntry in
        let seed = ProjectIdentity.seed(forCWD: "/demo/\(rarity.rawValue)")
        let xp = i * 6   // 0,6,12,18,24,30 → spans stages 1→3
        let aimon = AIMon(id: UUID(), seed: seed, name: NameGenerator.name(seed: seed),
                          personality: PersonalityGenerator.personality(seed: seed),
                          rarity: rarity, projectCWD: "/demo/\(rarity.rawValue)",
                          createdAt: created, lastSeenAt: created, xp: xp)
        let img = appearance.image(for: seed, rarity: rarity, stage: aimon.stage).nsImage()
        return StableEntry(aimon: aimon, image: img, isActive: i == 0)
    }
    let dir = "/tmp/aimon-render"; try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    let ok = MainActor.assumeIsolated { () -> Bool in
        // ImageRenderer can't lay out ScrollView/LazyVGrid, so render the cards eagerly (2 cols).
        let cards = HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) { ForEach(Array(entries.prefix(3))) { AIMonCard(entry: $0) } }
            VStack(spacing: 16) { ForEach(Array(entries.dropFirst(3).prefix(3))) { AIMonCard(entry: $0) } }
        }.padding(24).background(Color(nsColor: .windowBackgroundColor))
        let cardsRenderer = ImageRenderer(content: cards)
        cardsRenderer.proposedSize = ProposedViewSize(width: 480, height: nil)
        let detail = AIMonDetailContent(entry: entries.last!)
            .frame(width: 400).background(Color(nsColor: .windowBackgroundColor))
        let detailRenderer = ImageRenderer(content: detail)
        detailRenderer.proposedSize = ProposedViewSize(width: 400, height: nil)
        guard let cImg = cardsRenderer.nsImage, let cTiff = cImg.tiffRepresentation,
              let cRep = NSBitmapImageRep(data: cTiff), let cPng = cRep.representation(using: .png, properties: [:]),
              let dImg = detailRenderer.nsImage, let dTiff = dImg.tiffRepresentation,
              let dRep = NSBitmapImageRep(data: dTiff), let dPng = dRep.representation(using: .png, properties: [:])
        else { return false }
        try? cPng.write(to: URL(fileURLWithPath: "\(dir)/stable.png"))
        try? dPng.write(to: URL(fileURLWithPath: "\(dir)/detail.png"))
        return true
    }
    print(ok ? "wrote \(dir)/stable.png and detail.png" : "stable render failed")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar agent: no dock icon
app.run()
