import XCTest
@testable import AIMonCore

final class AIMonRegistryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aimon-reg-\(UUID().uuidString)").appendingPathComponent("registry.json")
    }

    func test_mint_isSeedDerivedAndStable() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reg = AIMonRegistry(fileURL: url)
        let a = reg.aimon(forProjectCWD: "/Users/roman/Projects/aimon", now: now)
        XCTAssertEqual(a.seed, ProjectIdentity.seed(forCWD: "/Users/roman/Projects/aimon"))
        XCTAssertEqual(a.name, NameGenerator.name(seed: a.seed))
        XCTAssertEqual(a.personality, PersonalityGenerator.personality(seed: a.seed))
        XCTAssertEqual(a.rarity, RarityGenerator.rarity(seed: a.seed))
        // same project → same record (identity, incl. id)
        XCTAssertEqual(reg.aimon(forProjectCWD: "/Users/roman/Projects/aimon", now: now).id, a.id)
    }

    func test_persistsAcrossReload() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let id: UUID
        do {
            let reg = AIMonRegistry(fileURL: url)
            id = reg.aimon(forProjectCWD: "/x", now: now).id
            reg.updateFrame(StoredFrame(x: 1, y: 2, width: 3, height: 4), forProjectCWD: "/x")
        }
        let reloaded = AIMonRegistry(fileURL: url)
        let a = reloaded.aimon(forProjectCWD: "/x")
        XCTAssertEqual(a?.id, id, "same id after reload → identity persisted, not re-minted")
        XCTAssertEqual(a?.lastFrame, StoredFrame(x: 1, y: 2, width: 3, height: 4))
    }

    func test_all_listsEveryProjectsAIMon() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reg = AIMonRegistry(fileURL: url)
        reg.aimon(forProjectCWD: "/a", now: now)
        reg.aimon(forProjectCWD: "/b", now: now.addingTimeInterval(10))
        XCTAssertEqual(reg.all().map(\.projectCWD), ["/a", "/b"])   // sorted by createdAt
    }

    func test_rename() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reg = AIMonRegistry(fileURL: url)
        reg.aimon(forProjectCWD: "/x", now: now)
        reg.rename(projectCWD: "/x", to: "Sparky")
        XCTAssertEqual(reg.aimon(forProjectCWD: "/x")?.name, "Sparky")
    }

    func test_missingFile_startsEmpty() {
        XCTAssertEqual(AIMonRegistry(fileURL: tempURL()).all().count, 0)
    }

    func test_addXP_accumulatesAndReportsEvolution() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reg = AIMonRegistry(fileURL: url)
        reg.aimon(forProjectCWD: "/x", now: now)

        let r1 = reg.addXP(5, forProjectCWD: "/x", now: now)
        XCTAssertEqual(r1?.aimon.xp, 5)
        XCTAssertEqual(r1?.didEvolve, false)
        XCTAssertEqual(r1?.toStage, 1)

        let r2 = reg.addXP(5, forProjectCWD: "/x", now: now)   // 10 total → crosses into stage 2
        XCTAssertEqual(r2?.aimon.xp, 10)
        XCTAssertEqual(r2?.didEvolve, true)
        XCTAssertEqual(r2?.fromStage, 1)
        XCTAssertEqual(r2?.toStage, 2)

        XCTAssertNil(reg.addXP(1, forProjectCWD: "/unknown", now: now))
    }

    func test_xp_persistsAcrossReload() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let reg = AIMonRegistry(fileURL: url)
            reg.aimon(forProjectCWD: "/x", now: now)
            reg.addXP(12, forProjectCWD: "/x", now: now)
        }
        XCTAssertEqual(AIMonRegistry(fileURL: url).aimon(forProjectCWD: "/x")?.xp, 12)
    }

    func test_decodesLegacyRecordWithoutXP() throws {
        // A record written before evolution existed has no "xp" key → must default to 0, not throw.
        let json = """
        {"id":"\(UUID().uuidString)","seed":7,"name":"Old",
         "personality":{"enthusiasm":10,"patience":20,"chaos":30,"wisdom":40,"snark":50},
         "rarity":"rare","projectCWD":"/x","createdAt":0,"lastSeenAt":0}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AIMon.self, from: json)
        XCTAssertEqual(decoded.xp, 0)
        XCTAssertEqual(decoded.stage, 1)
        XCTAssertEqual(decoded.name, "Old")
    }
}
