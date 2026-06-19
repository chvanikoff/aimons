import Foundation

/// A persisted window frame (avoids depending on CoreGraphics' Codable conformance).
public struct StoredFrame: Codable, Equatable, Sendable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

/// A persistent companion identity, bound to a project. Appearance is *derived* from `seed`
/// (not stored); everything a human-facing "stable" needs is here.
public struct AIMon: Codable, Equatable, Sendable {
    public let id: UUID
    public let seed: UInt64
    public var name: String
    /// The *base* (seed-derived, at-mint) personality. Maturity is applied on top — see
    /// `effectivePersonality`. Stored as the base so growth is reproducible and reversible.
    public let personality: Personality
    public let rarity: Rarity
    public let projectCWD: String
    public let createdAt: Date
    public var lastSeenAt: Date
    public var lastFrame: StoredFrame?
    /// Experience accrued from being active. Drives evolution stage.
    public var xp: Int

    public init(id: UUID, seed: UInt64, name: String, personality: Personality, rarity: Rarity,
                projectCWD: String, createdAt: Date, lastSeenAt: Date, lastFrame: StoredFrame? = nil,
                xp: Int = 0) {
        self.id = id; self.seed = seed; self.name = name; self.personality = personality
        self.rarity = rarity; self.projectCWD = projectCWD; self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt; self.lastFrame = lastFrame; self.xp = xp
    }

    /// The current evolution stage (1…3), derived from xp.
    public var stage: Int { Evolution.stage(forXP: xp) }

    /// Personality as matured by the creature's stage — what speech and the Stable should show.
    public var effectivePersonality: Personality { Evolution.apply(personality, stage: stage) }

    // Tolerant decoding: records written before evolution existed have no `xp` → default to 0.
    private enum CodingKeys: String, CodingKey {
        case id, seed, name, personality, rarity, projectCWD, createdAt, lastSeenAt, lastFrame, xp
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        seed = try c.decode(UInt64.self, forKey: .seed)
        name = try c.decode(String.self, forKey: .name)
        personality = try c.decode(Personality.self, forKey: .personality)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        projectCWD = try c.decode(String.self, forKey: .projectCWD)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastSeenAt = try c.decode(Date.self, forKey: .lastSeenAt)
        lastFrame = try c.decodeIfPresent(StoredFrame.self, forKey: .lastFrame)
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
    }
}

/// Outcome of granting xp: the updated record, and whether it crossed into a new stage.
public struct EvolutionResult: Equatable, Sendable {
    public let aimon: AIMon
    public let didEvolve: Bool
    public let fromStage: Int
    public let toStage: Int
}

/// Owns the stable of AIMons and project→AIMon bindings, persisted as JSON. Identity is stable:
/// the same project cwd always mints the same creature (seed-derived), and the record persists
/// name, rarity, personality, timestamps, and last window position across launches.
public final class AIMonRegistry {
    private let fileURL: URL
    private var byProject: [String: AIMon]

    public init(fileURL: URL = AIMonRegistry.defaultFileURL()) {
        self.fileURL = fileURL
        self.byProject = AIMonRegistry.load(from: fileURL) ?? [:]
    }

    public static func defaultFileURL() -> URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("AIMon", isDirectory: true).appendingPathComponent("registry.json")
    }

    /// The project's resident AIMon — existing binding, or freshly minted + persisted.
    @discardableResult
    public func aimon(forProjectCWD cwd: String, now: Date) -> AIMon {
        if var existing = byProject[cwd] {
            existing.lastSeenAt = now
            byProject[cwd] = existing
            save()
            return existing
        }
        let seed = ProjectIdentity.seed(forCWD: cwd)
        let minted = AIMon(id: UUID(), seed: seed,
                           name: NameGenerator.name(seed: seed),
                           personality: PersonalityGenerator.personality(seed: seed),
                           rarity: RarityGenerator.rarity(seed: seed),
                           projectCWD: cwd, createdAt: now, lastSeenAt: now)
        byProject[cwd] = minted
        save()
        return minted
    }

    public func all() -> [AIMon] {
        byProject.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func aimon(forProjectCWD cwd: String) -> AIMon? { byProject[cwd] }

    /// Persist the last on-screen frame for a project's AIMon (best-effort).
    public func updateFrame(_ frame: StoredFrame, forProjectCWD cwd: String) {
        guard var aimon = byProject[cwd] else { return }
        aimon.lastFrame = frame
        byProject[cwd] = aimon
        save()
    }

    /// Grant experience to a project's AIMon and report whether it evolved. No-op (nil) if unknown.
    @discardableResult
    public func addXP(_ amount: Int, forProjectCWD cwd: String, now: Date) -> EvolutionResult? {
        guard var aimon = byProject[cwd] else { return nil }
        let from = aimon.stage
        aimon.xp += max(0, amount)
        aimon.lastSeenAt = now
        let to = aimon.stage
        byProject[cwd] = aimon
        save()
        return EvolutionResult(aimon: aimon, didEvolve: to > from, fromStage: from, toStage: to)
    }

    /// Insert or replace a record (keyed by its projectCWD). Used to seed showcase/demo creatures.
    public func upsert(_ aimon: AIMon) {
        byProject[aimon.projectCWD] = aimon
        save()
    }

    public func rename(projectCWD cwd: String, to name: String) {
        guard var aimon = byProject[cwd] else { return }
        aimon.name = name
        byProject[cwd] = aimon
        save()
    }

    // MARK: - Persistence (best-effort; identity re-mints deterministically if the file is lost)

    private struct File: Codable { var byProject: [String: AIMon] }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(File(byProject: byProject)).write(to: fileURL, options: .atomic)
        } catch {
            // Non-fatal: in-memory state stays correct; identity is reproducible from seeds.
        }
    }

    private static func load(from url: URL) -> [String: AIMon]? {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return file.byProject
    }
}
