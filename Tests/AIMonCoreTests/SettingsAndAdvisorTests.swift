import XCTest
@testable import AIMonCore

final class SettingsAndAdvisorTests: XCTestCase {
    private func gb(_ n: Double) -> UInt64 { UInt64(n * 1_073_741_824) }

    func test_advisor_tiersByRAM() {
        XCTAssertEqual(HardwareAdvisor.recommendedModel(forRAMBytes: gb(16)).model, "llama3.2:3b")
        XCTAssertEqual(HardwareAdvisor.recommendedModel(forRAMBytes: gb(24)).model, "qwen2.5:7b")
        XCTAssertEqual(HardwareAdvisor.recommendedModel(forRAMBytes: gb(32)).model, "qwen2.5:14b")
        XCTAssertEqual(HardwareAdvisor.recommendedModel(forRAMBytes: gb(64)).model, "qwen2.5:14b")
        XCTAssertGreaterThan(HardwareAdvisor.recommendedModel(forRAMBytes: gb(64)).approxSizeGB, 0)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aimon-set-\(UUID().uuidString)").appendingPathComponent("settings.json")
    }

    func test_settings_defaults() {
        let s = SettingsStore(fileURL: tempURL()).settings
        XCTAssertTrue(s.ollamaEnabled)
        XCTAssertNil(s.selectedModel)
    }

    func test_settings_persistAcrossReload() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SettingsStore(fileURL: url)
        store.update { $0.ollamaEnabled = false; $0.selectedModel = "qwen2.5:7b" }
        let reloaded = SettingsStore(fileURL: url).settings
        XCTAssertFalse(reloaded.ollamaEnabled)
        XCTAssertEqual(reloaded.selectedModel, "qwen2.5:7b")
    }

    func test_settings_toleratesEmptyJSON() {
        let url = tempURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: url)
        let s = SettingsStore(fileURL: url).settings
        XCTAssertTrue(s.ollamaEnabled, "missing keys fall back to defaults")
    }
}
