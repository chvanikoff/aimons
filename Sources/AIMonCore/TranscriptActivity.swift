import Foundation

/// A single activity-relevant fact extracted from one transcript line.
public enum TranscriptSignal: Equatable, Sendable {
    case toolUse(name: String, target: String?)   // target = file basename or short command
    case toolError                                  // a tool_result with is_error
    case turnEnded                                  // assistant stop_reason == end_turn (likely waiting)
}

public enum TranscriptActivityDecoder {
    /// Extract activity signals from one JSONL transcript line. Tolerant of every other shape.
    /// `target` is deliberately coarse — a file *basename* or a truncated command — never a full
    /// path, to avoid leaking paths/secrets into speech.
    public static func signals(fromLine line: String) -> [TranscriptSignal] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let type = object["type"] as? String
        let message = object["message"] as? [String: Any]
        var signals: [TranscriptSignal] = []

        if let content = message?["content"] as? [[String: Any]] {
            for item in content {
                switch item["type"] as? String {
                case "tool_use":
                    let name = item["name"] as? String ?? "?"
                    signals.append(.toolUse(name: name, target: target(input: item["input"] as? [String: Any])))
                case "tool_result":
                    if (item["is_error"] as? Bool) == true { signals.append(.toolError) }
                default:
                    break
                }
            }
        }
        if type == "assistant", (message?["stop_reason"] as? String) == "end_turn" {
            signals.append(.turnEnded)
        }
        return signals
    }

    private static func target(input: [String: Any]?) -> String? {
        guard let input else { return nil }
        if let path = input["file_path"] as? String, !path.isEmpty { return (path as NSString).lastPathComponent }
        if let command = input["command"] as? String, !command.isEmpty { return String(command.prefix(60)) }
        return nil
    }
}

/// What a session is doing, coarsely — the salient thing worth a remark.
public enum SessionActivity: Equatable, Sendable {
    case editing(file: String)
    case running(command: String)
    case testing
    case error
    case waiting
}

public enum ActivityClassifier {
    /// Reduce a batch of new signals to the single most salient activity (nil if nothing notable —
    /// e.g. only reads/searches/thinking). Salience: error > testing > editing > running > waiting.
    public static func activity(from signals: [TranscriptSignal]) -> SessionActivity? {
        var best: SessionActivity?
        var bestRank = Int.max
        for signal in signals {
            guard let (activity, rank) = classify(signal), rank < bestRank else { continue }
            best = activity
            bestRank = rank
        }
        return best
    }

    private static func classify(_ signal: TranscriptSignal) -> (SessionActivity, Int)? {
        switch signal {
        case .toolError:
            return (.error, 0)
        case .turnEnded:
            return (.waiting, 4)
        case .toolUse(let name, let target):
            switch name {
            case "Bash":
                let command = target ?? ""
                return isTestCommand(command) ? (.testing, 1) : (.running(command: command), 3)
            case "Edit", "MultiEdit", "Write", "NotebookEdit":
                return (.editing(file: target ?? "a file"), 2)
            default:
                return nil   // Read / Grep / Glob / etc. — not worth speaking about
            }
        }
    }

    private static func isTestCommand(_ command: String) -> Bool {
        let c = command.lowercased()
        return c.contains("test") || c.contains("spec") || c.contains("jest")
    }
}

/// Reads only the lines appended to a transcript since the last call (offset tailing), so the
/// monster reacts to *new* activity without re-scanning history or re-reading multi-MB files.
public final class TranscriptTailReader {
    private var offsets: [String: UInt64] = [:]

    public init() {}

    public func newLines(atPath path: String) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0

        guard var start = offsets[path] else {
            offsets[path] = size   // first sight of this file → prime to EOF, don't replay history
            return []
        }
        if start > size { start = 0 }      // file shrank (rotated/new session) → start over
        guard start < size else { return [] }

        try? handle.seek(toOffset: start)
        let data = handle.readDataToEndOfFile()
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return [] }  // no complete line yet; keep offset
        offsets[path] = start + UInt64(lastNewline) + 1
        return String(decoding: data[data.startIndex...lastNewline], as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}
