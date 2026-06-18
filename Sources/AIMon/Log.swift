import os
import Foundation

/// Leveled logging spine. Each message goes to unified logging (structured, filterable,
/// production-appropriate) AND, in DEBUG builds, is echoed to stderr so it's visible when
/// running from a terminal (`swift run`) without needing `log stream`.
///
/// Unified-log access:
///   log stream --predicate 'subsystem == "io.romanc.aimon"' --level debug
struct AIMonLog {
    private let logger: Logger
    private let category: String

    init(_ category: String) {
        self.category = category
        self.logger = Logger(subsystem: "io.romanc.aimon", category: category)
    }

    /// Notable, persisted events (spawn/despawn, probe up/down).
    func notice(_ message: @autoclosure () -> String) {
        let m = message()
        logger.notice("\(m, privacy: .public)")
        echo(m)
    }

    /// Failures the user/dev should be able to find.
    func error(_ message: @autoclosure () -> String) {
        let m = message()
        logger.error("\(m, privacy: .public)")
        echo(m)
    }

    /// High-volume decision inputs; live-stream / DEBUG-stderr only.
    func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        let m = message()
        logger.debug("\(m, privacy: .public)")
        echo(m)
        #endif
    }

    private func echo(_ message: String) {
        #if DEBUG
        FileHandle.standardError.write(Data("AIMon[\(category)] \(message)\n".utf8))
        #endif
    }
}

enum Log {
    static let lifecycle = AIMonLog("lifecycle")
    static let watcher = AIMonLog("watcher")
}
