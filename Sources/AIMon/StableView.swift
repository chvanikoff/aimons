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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 16)], spacing: 16) {
                        ForEach(entries) { AIMonCard(entry: $0) }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 620, minHeight: 460)
    }
}

struct AIMonCard: View {
    let entry: StableEntry

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                spriteView
                if entry.isActive {
                    Label("live", systemImage: "circle.fill")
                        .labelStyle(.iconOnly).foregroundStyle(.green).font(.system(size: 10))
                        .padding(6)
                }
            }
            HStack(spacing: 6) {
                Text(entry.aimon.name).font(.headline)
                RarityBadge(rarity: entry.aimon.rarity)
            }
            TraitBars(personality: entry.aimon.personality)
            Text(projectName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(rarityColor(entry.aimon.rarity).opacity(0.5), lineWidth: 1.5))
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
