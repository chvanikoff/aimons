import Foundation

/// User-tunable settings, persisted as JSON alongside the registry.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Whether to use a local Ollama model for speech (falls back to templates when off/unavailable).
    public var ollamaEnabled: Bool
    /// The chosen installed model (nil → not chosen yet; the engine then uses templates).
    public var selectedModel: String?
    /// True once the user has answered the launch "download a model?" prompt, so we don't re-nag.
    public var dismissedModelOffer: Bool

    public init(ollamaEnabled: Bool = true, selectedModel: String? = nil, dismissedModelOffer: Bool = false) {
        self.ollamaEnabled = ollamaEnabled
        self.selectedModel = selectedModel
        self.dismissedModelOffer = dismissedModelOffer
    }

    private enum CodingKeys: String, CodingKey { case ollamaEnabled, selectedModel, dismissedModelOffer }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ollamaEnabled = try c.decodeIfPresent(Bool.self, forKey: .ollamaEnabled) ?? true
        selectedModel = try c.decodeIfPresent(String.self, forKey: .selectedModel)
        dismissedModelOffer = try c.decodeIfPresent(Bool.self, forKey: .dismissedModelOffer) ?? false
    }
}

/// Loads/saves `AppSettings` to disk (best-effort; defaults if missing or unreadable).
///
/// Thread-safe: `settings` is read from the main thread (Settings UI, launch check) AND off-main
/// (the speech Task resolving which model to use), while writes come from the main thread. A lock
/// guards the storage so reads return a consistent value-type snapshot and never race a write.
public final class SettingsStore {
    private let fileURL: URL
    private let lock = NSLock()
    private var _settings: AppSettings

    public init(fileURL: URL = SettingsStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self._settings = decoded
        } else {
            self._settings = AppSettings()
        }
    }

    public static func defaultFileURL() -> URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("AIMon", isDirectory: true).appendingPathComponent("settings.json")
    }

    /// A consistent snapshot of the current settings (safe to read from any thread).
    public var settings: AppSettings {
        lock.lock(); defer { lock.unlock() }
        return _settings
    }

    /// Mutate and persist (atomically with respect to readers).
    @discardableResult
    public func update(_ mutate: (inout AppSettings) -> Void) -> AppSettings {
        lock.lock()
        mutate(&_settings)
        let snapshot = _settings
        lock.unlock()
        save(snapshot)
        return snapshot
    }

    private func save(_ snapshot: AppSettings) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch { /* non-fatal; in-memory state stays correct */ }
    }
}
