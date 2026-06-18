import Foundation

/// The minimal facts the watcher needs from a transcript line.
public struct TranscriptMeta: Equatable {
    public let sessionId: String
    public let cwd: String?

    public init(sessionId: String, cwd: String?) {
        self.sessionId = sessionId
        self.cwd = cwd
    }
}

public enum TranscriptDecoder {
    /// Decodes a single JSONL line into its sessionId + cwd. Returns nil for blank,
    /// unparseable, or sessionId-less lines. Deliberately tolerant — transcripts contain
    /// many line shapes we don't care about.
    public static func meta(fromLine line: String) -> TranscriptMeta? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let sessionId = dict["sessionId"] as? String else { return nil }
        return TranscriptMeta(sessionId: sessionId, cwd: dict["cwd"] as? String)
    }
}
