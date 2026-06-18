import Foundation
import AIMonCore

/// Real `ProcessProbe`: shells out to `ps` (to find `claude` CLI pids by argv[0] basename,
/// since the CLI's process *name* is its version string) then `lsof` (each pid's cwd).
///
/// Designed to be invoked on a background queue — every subprocess has a hard deadline and
/// is killed on expiry, returning `nil` so the engine degrades to the mtime heuristic. A
/// hung `lsof` (stale network mount) can therefore never park the main thread.
final class ProcessProbeCLI: ProcessProbe {
    private let config: WatcherConfig

    init(config: WatcherConfig = .default) {
        self.config = config
    }

    func liveCWDs() -> [String]? {
        guard let ps = run("/bin/ps", ["-axww", "-o", "pid=", "-o", "command="]) else { return nil }
        let pids = ProcessScan.claudePIDs(fromPS: ps)
        if pids.isEmpty { return [] }   // no claude CLI running — trustworthy empty
        let lsof = run("/usr/sbin/lsof", ["-a", "-p", pids.joined(separator: ","), "-d", "cwd", "-Fn"])
        guard let cwds = ProcessScan.resolveLiveCWDs(claudePIDs: pids, lsofOutput: lsof) else { return nil }
        return cwds.map(PathNormalizer.standardize)
    }

    /// Run a subprocess, draining stdout on a concurrent reader (so a full pipe buffer can't
    /// deadlock it) and killing it after `config.probeTimeout`. Returns its stdout, or `nil`
    /// if it failed to launch or timed out.
    private func run(_ launchPath: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        let readQueue = DispatchQueue(label: "io.romanc.aimon.probe.read")
        let readDone = DispatchSemaphore(value: 0)
        let collected = Box()
        readQueue.async {
            collected.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }

        if exited.wait(timeout: .now() + config.probeTimeout) == .timedOut {
            process.terminate()                        // SIGTERM the wedged probe
            _ = exited.wait(timeout: .now() + 0.5)
            _ = readDone.wait(timeout: .now() + 0.5)
            return nil                                 // timeout → probe unavailable
        }
        _ = readDone.wait(timeout: .now() + 1.0)
        return String(data: collected.data, encoding: .utf8) ?? ""
    }

    /// Boxed buffer so the concurrent reader and the waiter share one storage; the semaphore
    /// provides the happens-before ordering for the read after the write.
    private final class Box { var data = Data() }
}
