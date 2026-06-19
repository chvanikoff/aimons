import Foundation

/// Talks to a local Ollama server for *management*: is it there, what models are installed, and
/// pulling a model with progress. (Speech generation itself lives in OllamaProvider.)
final class OllamaService {
    let host: URL
    init(host: URL = URL(string: "http://localhost:11434")!) { self.host = host }

    /// True if the Ollama server answers (i.e. it's installed AND running).
    func isRunning() async -> Bool {
        var req = URLRequest(url: host.appendingPathComponent("api/tags"))
        req.timeoutInterval = 2
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    /// True if the Ollama app/CLI appears installed (even if the server isn't currently up).
    func isInstalled() -> Bool {
        ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Names of locally-installed models (sorted), or [] if the server isn't reachable.
    func installedModels() async -> [String] {
        var req = URLRequest(url: host.appendingPathComponent("api/tags"))
        req.timeoutInterval = 3
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    /// Pull a model, reporting overall download fraction (0…1). Streams Ollama's `/api/pull`
    /// progress, aggregating across layers (each layer has its own digest/total/completed) so the
    /// percentage rises monotonically instead of resetting per layer.
    func pull(_ model: String, progress: @escaping (Double) -> Void) async throws {
        var req = URLRequest(url: host.appendingPathComponent("api/pull"))
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": model, "stream": true])

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw OllamaServiceError.httpError }

        var totalByDigest: [String: Double] = [:]
        var doneByDigest: [String: Double] = [:]
        for try await line in bytes.lines {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            if let err = obj["error"] as? String { throw OllamaServiceError.pullFailed(err) }
            if let digest = obj["digest"] as? String, let total = obj["total"] as? Double, total > 0 {
                totalByDigest[digest] = total
                doneByDigest[digest] = (obj["completed"] as? Double) ?? doneByDigest[digest] ?? 0
                let t = totalByDigest.values.reduce(0, +)
                let c = doneByDigest.values.reduce(0, +)
                if t > 0 { progress(min(1, c / t)) }
            }
            if (obj["status"] as? String) == "success" { progress(1) }
        }
    }

    /// Heuristic: is this model usable for chat/generation (vs an embedding-only model that would
    /// silently fail to produce speech)? Embedding models conventionally carry "embed" in the name.
    static func looksLikeChatModel(_ name: String) -> Bool {
        !name.lowercased().contains("embed")
    }

    enum OllamaServiceError: LocalizedError {
        case httpError, pullFailed(String)
        var errorDescription: String? {
            switch self {
            case .httpError: return "Ollama returned an error."
            case .pullFailed(let m): return m
            }
        }
    }
}
