import SwiftUI
import AIMonCore

/// One AIMon as shown in the Stable: its record, rendered sprite, and whether it's live now.
struct StableEntry: Identifiable {
    let aimon: AIMon
    let image: NSImage?
    let isActive: Bool
    var id: UUID { aimon.id }
}

/// The Stable — a gamified gallery of every AIMon you've collected (one per project).
struct StableView: View {
    let entries: [StableEntry]
    @State private var selected: StableEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("The Stable").font(.largeTitle.bold())
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                        ForEach(entries) { entry in
                            AIMonCard(entry: entry)
                                .onTapGesture { selected = entry }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .sheet(item: $selected) { AIMonDetailView(entry: $0) }
    }
}

struct AIMonCard: View {
    let entry: StableEntry
    private var rarity: Rarity { entry.aimon.rarity }
    private var tier: Int { rarityTier(rarity) }   // 0…5

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                spriteView
                if entry.aimon.stage > 1 {
                    Text("Lv\(entry.aimon.stage)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if entry.isActive {
                    Label("live", systemImage: "circle.fill")
                        .labelStyle(.iconOnly).foregroundStyle(.green).font(.system(size: 10))
                        .padding(6)
                }
            }
            HStack(spacing: 6) {
                Text(entry.aimon.name).font(.headline)
                RarityBadge(rarity: rarity)
            }
            StarRow(filled: tier + 1, color: rarityColor(rarity))
            TraitBars(personality: entry.aimon.effectivePersonality)
            Text(projectName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(cardGradient))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(rarityColor(rarity).opacity(0.35 + Double(tier) * 0.11),
                    lineWidth: 1 + CGFloat(tier) * 0.5))
        .shadow(color: tier >= 4 ? rarityColor(rarity).opacity(0.55) : .clear, radius: tier >= 4 ? 9 : 0)
        .contentShape(Rectangle())
    }

    // Rarer cards get a stronger rarity-tinted wash over the base surface.
    private var cardGradient: LinearGradient {
        let tint = rarityColor(rarity).opacity(Double(tier) * 0.05)
        return LinearGradient(colors: [Color(nsColor: .controlBackgroundColor).opacity(0.6),
                                       tint],
                              startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder private var spriteView: some View {
        if let image = entry.image {
            Image(nsImage: image).interpolation(.none).resizable()
                .frame(width: 84, height: 84)
        } else {
            RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.2)).frame(width: 84, height: 84)
        }
    }

    private var projectName: String {
        let name = (entry.aimon.projectCWD as NSString).lastPathComponent
        return name.isEmpty ? entry.aimon.projectCWD : name
    }
}

/// The full dossier for one creature, shown as a sheet when its card is tapped.
struct AIMonDetailView: View {
    let entry: StableEntry
    @Environment(\.dismiss) private var dismiss
    private var tier: Int { rarityTier(entry.aimon.rarity) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { AIMonDetailContent(entry: entry) }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 400, height: 560)
        .background(LinearGradient(colors: [rarityColor(entry.aimon.rarity).opacity(Double(tier) * 0.06),
                                            Color(nsColor: .windowBackgroundColor)],
                                   startPoint: .top, endPoint: .bottom))
    }
}

/// The scrollable body of the detail sheet (factored out so it can be rendered eagerly in tests —
/// ImageRenderer can't lay out a ScrollView's content).
struct AIMonDetailContent: View {
    let entry: StableEntry
    private var aimon: AIMon { entry.aimon }
    private var rarity: Rarity { aimon.rarity }
    private var tier: Int { rarityTier(rarity) }

    var body: some View {
        VStack(spacing: 16) {
            bigSprite
            VStack(spacing: 6) {
                Text(aimon.name).font(.system(size: 26, weight: .bold))
                HStack(spacing: 8) {
                    RarityBadge(rarity: rarity)
                    StarRow(filled: tier + 1, color: rarityColor(rarity))
                }
            }
            stageSection
            TraitBars(personality: aimon.effectivePersonality)
                .frame(maxWidth: 300)
            Divider()
            Text(BackstoryGenerator.backstory(for: aimon))
                .font(.callout).foregroundStyle(.primary.opacity(0.85))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            metaSection
        }
        .padding(24)
    }

    @ViewBuilder private var bigSprite: some View {
        Group {
            if let image = entry.image {
                Image(nsImage: image).interpolation(.none).resizable()
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.secondary.opacity(0.2))
            }
        }
        .frame(width: 150, height: 150)
        .shadow(color: tier >= 4 ? rarityColor(rarity).opacity(0.6) : .clear, radius: 14)
    }

    private var stageSection: some View {
        VStack(spacing: 4) {
            Text("Evolution — Stage \(aimon.stage) of \(Evolution.maxStage)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let toNext = Evolution.xpToNextStage(fromXP: aimon.xp) {
                ProgressView(value: stageProgress)
                    .frame(maxWidth: 240).tint(rarityColor(rarity))
                Text("\(toNext) xp to next stage").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("Fully evolved").font(.system(size: 10, weight: .medium)).foregroundStyle(rarityColor(rarity))
            }
        }
    }

    private var metaSection: some View {
        VStack(spacing: 2) {
            Text("Project: \((aimon.projectCWD as NSString).lastPathComponent)")
            Text("Discovered \(aimon.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(aimon.xp) xp")
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
    }

    private var stageProgress: Double {
        let s = aimon.stage
        guard s < Evolution.maxStage else { return 1 }
        let lower = Evolution.thresholds[s - 1], upper = Evolution.thresholds[s]
        guard upper > lower else { return 1 }
        return min(1, max(0, Double(aimon.xp - lower) / Double(upper - lower)))
    }
}

private struct StarRow: View {
    let filled: Int
    let color: Color
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(1, filled), id: \.self) { _ in
                Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(color)
            }
        }
    }
}

private struct RarityBadge: View {
    let rarity: Rarity
    var body: some View {
        Text(rarity.displayName.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(rarityColor(rarity)))
            .foregroundStyle(.white)
    }
}

private struct TraitBars: View {
    let personality: Personality
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
        HStack(spacing: 6) {
            Text(label).font(.system(size: 9)).frame(width: 64, alignment: .leading).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.18))
                    Capsule().fill(.tint).frame(width: geo.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 6)
            Text("\(value)").font(.system(size: 9, weight: .medium).monospacedDigit())
                .frame(width: 22, alignment: .trailing).foregroundStyle(.secondary)
        }
    }
}

/// Rarity's position in the ladder (0 = common … 5 = mythic).
private func rarityTier(_ rarity: Rarity) -> Int {
    Rarity.allCases.firstIndex(of: rarity) ?? 0
}

private func rarityColor(_ rarity: Rarity) -> Color {
    switch rarity {
    case .common:    return .gray
    case .uncommon:  return .green
    case .rare:      return .blue
    case .epic:      return .purple
    case .legendary: return .orange
    case .mythic:    return .pink
    }
}
