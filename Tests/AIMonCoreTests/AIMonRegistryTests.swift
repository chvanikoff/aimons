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
}
