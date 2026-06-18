import Foundation
import AIMonCore

/// Speech via a local Ollama server. Builds the prompt from a `SpeechContext`, POSTs to
/// `/api/generate` (non-streaming, short output), and returns a tidied one-line reply.
/// Any failure/timeout throws so the `SpeechEngine` falls back to the template floor.
final class OllamaProvider {
    private let endpoint: URL
    private let model: String
    private let timeout: TimeInterval

    init(host: URL = URL(string: "http://localhost:11434")!,
         model: String = "llama3.2:3b",
         timeout: TimeInterval = 8) {
        self.endpoint = host.appendingPathComponent("api/generate")
        self.model = model
        self.timeout = timeout
    }

    func line(for context: SpeechContext) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": SpeechPrompt.build(for: context),
            "stream": false,
            "options": ["temperature": 0.9, "num_predict": 40],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let line = OllamaResponseParser.line(fromJSON: data) else {
            throw OllamaError.badResponse
        }
        return line
    }

    enum OllamaError: Error { case badResponse }
}
