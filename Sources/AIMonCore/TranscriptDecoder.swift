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

    /// Scans transcript bytes line-by-line for the first record carrying a `cwd`.
    ///
    /// Splits only on the ASCII newline byte (0x0A), so a decode is never cut
    /// mid-multibyte-character — the failure mode of reading a fixed byte chunk and
    /// decoding the whole thing at once. A truncated final line (transcripts are
    /// appended live) simply fails to parse and is skipped.
    public static func firstCWD(in data: Data) -> String? {
        let newline: UInt8 = 0x0A
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: newline) ?? data.endIndex
            let line = data[start..<end]
            if !line.isEmpty,
               let object = try? JSONSerialization.jsonObject(with: Data(line)),
               let dict = object as? [String: Any],
               let cwd = dict["cwd"] as? String, !cwd.isEmpty {
                return cwd
            }
            if end == data.endIndex { break }
            start = data.index(after: end)
        }
        return nil
    }
}
