import os
import Foundation

/// Leveled logging spine. Each message goes to unified logging (structured, filterable) AND a
/// plain-text log file under Application Support (so users can find/share it from Settings), AND,
/// in DEBUG builds, stderr (visible under `swift run`).
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
        LogFile.shared.append(category, "NOTICE", m)
        echo(m)
    }

    /// Failures the user/dev should be able to find.
    func error(_ message: @autoclosure () -> String) {
        let m = message()
        logger.error("\(m, privacy: .public)")
        LogFile.shared.append(category, "ERROR", m)
        echo(m)
    }

    /// High-volume decision inputs; live-stream / DEBUG-stderr only.
    func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        let m = message()
        logger.debug("\(m, privacy: .public)")
        LogFile.shared.append(category, "DEBUG", m)
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

    /// Where the plain-text log file lives (for the Settings "reveal logs" affordance).
    static var fileURL: URL { LogFile.shared.url }
}

/// A small, thread-safe append-only text log. Rotates (truncates) if it grows past ~2 MB.
private final class LogFile {
    static let shared = LogFile()
    let url: URL
    private let maxBytes = 2_000_000
    private let queue = DispatchQueue(label: "io.romanc.aimon.logfile", qos: .utility)
    private var handle: FileHandle?
    private var bytesWritten = 0
    private var disabled = false
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    init() {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        url = support.appendingPathComponent("AIMon/logs", isDirectory: true).appendingPathComponent("aimon.log")
    }

    func append(_ category: String, _ level: String, _ message: String) {
        queue.async {
            guard !self.disabled else { return }
            if self.handle == nil { self.open() }
            guard let handle = self.handle else { return }
            let data = Data("\(self.formatter.string(from: Date())) [\(level)] \(category): \(message)\n".utf8)
            handle.write(data)
            self.bytesWritten += data.count
            if self.bytesWritten > self.maxBytes { self.rotate() }   // keep rotating mid-session
        }
    }

    private func open() {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let h = try? FileHandle(forWritingTo: url) else { disabled = true; return }
        handle = h
        h.seekToEndOfFile()
        if let attrs = try? fm.attributesOfItem(atPath: url.path), let size = attrs[.size] as? Int {
            bytesWritten = size
        } else {
            bytesWritten = 0
        }
    }

    /// Close, delete, and reopen fresh — so the file never grows unbounded and we don't keep a
    /// handle on a deleted inode.
    private func rotate() {
        try? handle?.close()
        handle = nil
        bytesWritten = 0
        try? FileManager.default.removeItem(at: url)   // reopened lazily on the next append
    }
}
