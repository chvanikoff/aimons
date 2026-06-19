import SwiftUI
import AIMonCore

/// One AIMon as shown in the Stable: its record, rendered sprite, and whether it's live now.
struct StableEntry: Identifiable {
    let aimon: AIMon
    let image: NSImage?
    let isActive: Bool
    var id: UUID { aimon.id }
}

/// The Aidex — a gallery of collectible trading cards, one per AIMon (aimon → ai-dex, à la
/// Pokémon → Pokédex). Tap a card to flip it and read that creature's backstory on the back. Card
/// art/frame styling escalates with rarity and evolution stage (à la MTG / Pokémon foils).
struct StableView: View {
    let entries: [StableEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Aidex").font(.largeTitle.bold())
                Spacer()
                Text("\(entries.count) collected").foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            if entries.isEmpty {
                Spacer()
                Text("No AIMons yet — open a Claude Code session in a project and one will appear.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(40)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: CardMetrics.width), spacing: 22)],
                              spacing: 22) {
                        ForEach(entries) { CollectibleCard(entry: $0) }
                    }
                    .padding(22)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }
}

enum CardMetrics {
    static let width: CGFloat = 210
    static let height: CGFloat = 294   // 2.5 : 3.5 trading-card ratio
    static let corner: CGFloat = 14
}

/// A two-sided collectible card that flips in 3D on tap to reveal the backstory.
struct CollectibleCard: View {
    let entry: StableEntry
    @State private var flipped = false

    var body: some View {
        ZStack {
            CardFront(entry: entry).opacity(flipped ? 0 : 1)
            CardBack(entry: entry).opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(width: CardMetrics.width, height: CardMetrics.height)
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .onTapGesture { withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { flipped.toggle() } }
        .shadow(color: RarityStyle.tier(entry.aimon.rarity) >= 4
                ? RarityStyle.primary(entry.aimon.rarity).opacity(0.5) : .black.opacity(0.25),
                radius: RarityStyle.tier(entry.aimon.rarity) >= 4 ? 12 : 5, y: 3)
    }
}

// MARK: - Card faces

struct CardFront: View {
    let entry: StableEntry
    private var aimon: AIMon { entry.aimon }
    private var rarity: Rarity { aimon.rarity }
    private var tier: Int { RarityStyle.tier(rarity) }

    var body: some View {
        VStack(spacing: 7) {
            titleBar
            artWindow
            typeLine
            statBox
            Spacer(minLength: 0)
            footer
        }
        .padding(11)
        .frame(width: CardMetrics.width, height: CardMetrics.height)
        .background(CardFrame(rarity: rarity))
    }

    private var titleBar: some View {
        HStack(spacing: 4) {
            Text(aimon.name).font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Image(systemName: "diamond.fill").font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.28)))
    }

    private var artWindow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(RarityStyle.artBackground(rarity))
            if let image = entry.image {
                Image(nsImage: image).interpolation(.none).resizable().scaledToFit().padding(14)
            }
            if entry.isActive {
                Label("live", systemImage: "circle.fill").labelStyle(.iconOnly)
                    .foregroundStyle(.green).font(.system(size: 9))
                    .padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(height: 116)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.55), lineWidth: 1.5))
    }

    private var typeLine: some View {
        HStack(spacing: 4) {
            Text(aimon.effectivePersonality.archetype.rawValue.capitalized)
                .font(.system(size: 10, weight: .semibold))
            StarRow(filled: tier + 1, color: .white)
            Spacer()
            if aimon.stage > 1 {
                Text("Lv\(aimon.stage)").font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(0.25)))
            }
        }
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 3)
    }

    private var statBox: some View {
        TraitBars(personality: aimon.effectivePersonality, color: .white)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.22)))
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text(rarity.displayName.uppercased()).font(.system(size: 8, weight: .black))
            Spacer()
            Text((aimon.projectCWD as NSString).lastPathComponent).font(.system(size: 8)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 4)
    }
}

struct CardBack: View {
    let entry: StableEntry
    private var aimon: AIMon { entry.aimon }
    private var rarity: Rarity { aimon.rarity }

    var body: some View {
        VStack(spacing: 12) {
            Text(aimon.name).font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Image(systemName: "sparkles").font(.system(size: 22)).foregroundStyle(.white.opacity(0.85))
            Text(BackstoryGenerator.backstory(for: aimon))
                .font(.system(size: 12, design: .serif)).italic()
                .foregroundStyle(.white.opacity(0.95))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.26)))
            Spacer(minLength: 0)
            Text("\(rarity.displayName) · Stage \(aimon.stage)/\(Evolution.maxStage)")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
            Text("tap to flip back").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .frame(width: CardMetrics.width, height: CardMetrics.height)
        .background(CardFrame(rarity: rarity))
    }
}

// MARK: - Shared frame & widgets

/// The rarity-themed card frame: a gradient body, a foil sheen for high tiers, and a coloured edge.
struct CardFrame: View {
    let rarity: Rarity
    private var tier: Int { RarityStyle.tier(rarity) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CardMetrics.corner).fill(RarityStyle.frameGradient(rarity))
            if tier >= 4 {   // legendary & mythic get a holographic sheen
                RoundedRectangle(cornerRadius: CardMetrics.corner)
                    .fill(RarityStyle.foilSheen).blendMode(.plusLighter).opacity(0.30)
            }
            RoundedRectangle(cornerRadius: CardMetrics.corner)
                .strokeBorder(RarityStyle.primary(rarity), lineWidth: 1.5 + CGFloat(tier) * 0.6)
            RoundedRectangle(cornerRadius: CardMetrics.corner)
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.5).padding(2)
        }
    }
}

struct StarRow: View {
    let filled: Int
    let color: Color
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<max(1, filled), id: \.self) { _ in
                Image(systemName: "star.fill").font(.system(size: 7)).foregroundStyle(color)
            }
        }
    }
}

struct TraitBars: View {
    let personality: Personality
    var color: Color = .accentColor
    var body: some View {
        VStack(spacing: 3) {
            bar("Enthusiasm", personality.enthusiasm)
            bar("Patience", personality.patience)
            bar("Chaos", personality.chaos)
            bar("Wisdom", personality.wisdom)
            bar("Snark", personality.snark)
        }
    }

    private func bar(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 8)).frame(width: 58, alignment: .leading)
                .foregroundStyle(color.opacity(0.85))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.18))
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 5)
            Text("\(value)").font(.system(size: 8, weight: .medium).monospacedDigit())
                .frame(width: 18, alignment: .trailing).foregroundStyle(color.opacity(0.85))
        }
    }
}

// MARK: - Rarity styling

enum RarityStyle {
    static func tier(_ rarity: Rarity) -> Int { Rarity.allCases.firstIndex(of: rarity) ?? 0 }

    static func primary(_ rarity: Rarity) -> Color {
        switch rarity {
        case .common:    return Color(red: 0.55, green: 0.57, blue: 0.60)
        case .uncommon:  return Color(red: 0.20, green: 0.70, blue: 0.40)
        case .rare:      return Color(red: 0.20, green: 0.50, blue: 0.90)
        case .epic:      return Color(red: 0.60, green: 0.35, blue: 0.85)
        case .legendary: return Color(red: 0.95, green: 0.60, blue: 0.15)
        case .mythic:    return Color(red: 0.95, green: 0.30, blue: 0.65)
        }
    }

    static func secondary(_ rarity: Rarity) -> Color {
        switch rarity {
        case .common:    return Color(red: 0.32, green: 0.34, blue: 0.38)
        case .uncommon:  return Color(red: 0.10, green: 0.42, blue: 0.30)
        case .rare:      return Color(red: 0.12, green: 0.26, blue: 0.55)
        case .epic:      return Color(red: 0.34, green: 0.18, blue: 0.55)
        case .legendary: return Color(red: 0.70, green: 0.32, blue: 0.06)
        case .mythic:    return Color(red: 0.55, green: 0.12, blue: 0.45)
        }
    }

    /// The card body gradient (darker, so white text and panels pop).
    static func frameGradient(_ rarity: Rarity) -> LinearGradient {
        LinearGradient(colors: [primary(rarity).opacity(0.95), secondary(rarity)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The art-window backdrop — a soft light panel tinted by rarity.
    static func artBackground(_ rarity: Rarity) -> LinearGradient {
        LinearGradient(colors: [.white.opacity(0.92), primary(rarity).opacity(0.22)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// A holographic rainbow sheen for legendary/mythic foils.
    static let foilSheen = AngularGradient(
        colors: [.pink, .purple, .blue, .cyan, .green, .yellow, .orange, .pink],
        center: .center)
}
