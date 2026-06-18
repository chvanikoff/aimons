/// Pure parsers for the output of the OS process probes the watcher shells out to.
///
/// Liveness of a Claude Code session is determined by whether its `claude` CLI
/// process is still alive — not by transcript mtime, which can't tell an idle
/// session from an ended one. The CLI's process *name* is its version string
/// (e.g. "2.1.181"), so it can't be matched with `pgrep`/`lsof -c`; instead we
/// match the argv[0] basename from `ps`, then read each pid's cwd from `lsof`.
public enum ProcessScan {
    /// PIDs whose argv[0] basename is exactly "claude", parsed from the output of
    /// `ps -axww -o pid= -o command=`. Excludes the desktop app ("Claude Helper"),
    /// MCP node servers, etc.
    public static func claudePIDs(fromPS output: String) -> [String] {
        var pids: [String] = []
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let sep = line.firstIndex(of: " ") else { continue }
            let pid = String(line[..<sep])
            guard pid.allSatisfy(\.isNumber), !pid.isEmpty else { continue }
            let command = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            let argv0 = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
            let basename = argv0.split(separator: "/").last.map(String.init) ?? argv0
            if basename == "claude" { pids.append(pid) }
        }
        return pids
    }

    /// Working directories parsed from `lsof -a -p <pids> -d cwd -Fn` output:
    /// one `n<path>` line per process. Returns one entry per process (duplicates
    /// preserved, so callers can count concurrent sessions sharing a cwd).
    public static func cwds(fromLSOF output: String) -> [String] {
        output.split(separator: "\n")
            .filter { $0.hasPrefix("n") }
            .map { String($0.dropFirst()) }
    }

    /// Tallies cwds into a per-directory live-process count.
    public static func counts(of cwds: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for cwd in cwds { result[cwd, default: 0] += 1 }
        return result
    }

    /// Combines the two probe stages into a tri-state result:
    ///   - `nil`  → probe unavailable; caller must degrade to the mtime heuristic.
    ///   - `[]`   → no `claude` CLI running (a *trustworthy* empty: every session may end).
    ///   - `[..]` → the live cwds.
    ///
    /// `claudePIDs == nil` means `ps` failed. `lsofOutput == nil` means `lsof` couldn't run
    /// (or timed out). Crucially, the **count guard** is the authority: if `lsof` returns
    /// fewer cwds than pids — which happens when a pid dies in the TOCTOU gap between the
    /// `ps` and `lsof` shell-outs (lsof drops it and exits non-zero, verified empirically) —
    /// we return `nil` rather than a partial undercount that would wrongly despawn a live
    /// session. lsof's own exit status is quirky and unreliable, so it is deliberately not used.
    public static func resolveLiveCWDs(claudePIDs: [String]?, lsofOutput: String?) -> [String]? {
        guard let pids = claudePIDs else { return nil }      // ps failed
        if pids.isEmpty { return [] }                         // no claude running — trustworthy empty
        guard let output = lsofOutput else { return nil }     // lsof couldn't run
        let resolved = cwds(fromLSOF: output)
        guard resolved.count == pids.count else { return nil }          // undercount → unreliable
        return resolved
    }
}
