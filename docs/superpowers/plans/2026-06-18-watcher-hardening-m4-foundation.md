# Watcher Hardening & M4 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate two real defects (UI-freeze on a hung probe; resumed/idle sessions never spawning), and move the session-tracking *orchestration* out of the untestable executable target into a pure, dependency-injected, fully-tested engine in `AIMonCore` — so the codebase is precise, observable, and ready to carry stateful speaking monsters in M4 without rework.

**Architecture:** Today the pure reconciler (`WatcherReconciler`) is well-tested, but the stateful glue that composes it (the tick loop, `canSpawn` against mutating state, `standardize()`, cwd resolution, the `ps`/`lsof` exec) lives in `Sources/AIMon/TranscriptWatcher.swift` — the executable target, which has zero automated tests, and is exactly where all three prior bugs lived. This plan inverts that: nearly all logic moves into `AIMonCore` behind injected protocols (`TranscriptStore`, `ProcessProbe`, `Clock`), leaving the shell to do only Timer + Process-exec + AppKit. A single unified decision — **the monsters for a directory are the `P` most-recently-modified transcripts there, where `P` = live `claude` process count** — replaces the current two-stage spawn-candidate + `canSpawn` split, collapsing the spawn/despawn-signal-asymmetry bug class (idle false-despawn, Ctrl-C flap, duplicate sibling, and the new resume-never-spawn) into one rule. The probe moves off the main thread with a hard timeout; UI-owning types become `@MainActor`.

**Tech Stack:** Swift 5.9 (Swift-5 language mode), SwiftPM, AppKit + SpriteKit, `os.Logger`, `Foundation.Process`/`Pipe`, `DispatchQueue`. macOS 13+.

## Global Constraints

- macOS 13+, Swift tools 5.9, **Swift-5 language mode** (no strict-concurrency build; `@MainActor` used as an isolation marker, not enforced by the compiler). Verbatim from `Package.swift`.
- `AIMonCore` is a **pure-logic / Foundation-only library**: NO AppKit, SpriteKit, or `os.Logger`-via-AppKit. It MAY use `Foundation` (incl. `Process`, `FileManager`, `URL`, `os.Logger`). All session-tracking logic and the real filesystem store live here so they are unit-testable.
- `AIMon` (executable) holds ONLY: `NSApplication`/AppKit/SpriteKit, the `Timer`, the `Process`-exec probe, and thin wiring. It is verified by the user/assistant launching the app, never by unit tests.
- TDD: every behavioral change is a failing test first, then minimal code. Per-task commits. Build (`swift build`) and full suite (`swift test`) green at the end of every task.
- The unified invariant (preserve across all changes): **# monsters for a cwd == # live `claude` processes for that cwd**; when transcripts outnumber processes, keep the most-recently-modified; when the probe is unavailable (`nil`), degrade to the mtime stale-timeout heuristic.
- Do NOT re-introduce the three fixed bugs. Every engine change must keep their regression tests green.

---

## File Structure

**Create (in `AIMonCore`):**
- `Sources/AIMonCore/WatcherConfig.swift` — validated typed tunables.
- `Sources/AIMonCore/PathNormalizer.swift` — `standardize(_:)` symlink/path canonicalization (moved from the shell).
- `Sources/AIMonCore/SessionWatchEngine.swift` — `SessionRef`, `WatchOutcome`, protocols `TranscriptStore`/`ProcessProbe`/`Clock`, and the stateful pure engine implementing the top-P decision.
- `Sources/AIMonCore/FileTranscriptStore.swift` — real `FileManager`-based `TranscriptStore` (testable via temp dirs).

**Create (in `AIMon`):**
- `Sources/AIMon/Log.swift` — `os.Logger` instances + helpers.
- `Sources/AIMon/ProcessProbeCLI.swift` — real `ProcessProbe`: off-main `ps`/`lsof` exec with hard timeout.

**Modify:**
- `Sources/AIMonCore/SessionWatch.swift` — add `cwd` to `TranscriptFile` (additive); after Task 7, delete `WatcherReconciler.reconcile`/`canSpawn` (superseded by the engine).
- `Sources/AIMonCore/TranscriptDecoder.swift` — add `firstCWD(in:)` byte-scanning extractor.
- `Sources/AIMonCore/ProcessScan.swift` — add `resolveLiveCWDs(...)` tri-state combiner.
- `Sources/AIMon/TranscriptWatcher.swift` — rewritten to a thin shell driving the engine.
- `Sources/AIMon/AppDelegate.swift` — `@MainActor`, route `WatchOutcome`, `applicationWillTerminate`, logging, dev-spawn despawn, remove dead guard.
- `Sources/AIMon/CompanionWindow.swift`, `CompanionScene.swift` — `deinit` logging, `isReleasedWhenClosed=false`, failable scene init, `WatcherConfig`/`RenderConfig` sizing.
- `Tests/AIMonCoreTests/*` — new engine/store/config/decoder/probe tests; delete `WatcherReconcilerTests` when the reconciler is removed (Task 7).

---

## Task 1: Typed `WatcherConfig` with validated invariants

**Files:**
- Create: `Sources/AIMonCore/WatcherConfig.swift`
- Test: `Tests/AIMonCoreTests/WatcherConfigTests.swift`

**Interfaces:**
- Produces: `public struct WatcherConfig { let pollInterval, liveWindow, staleTimeout, probeTimeout: TimeInterval; let transcriptReadBytes: Int; init(...) }`, `static let `default``. A `RenderConfig` struct (`pixelScale`, `minScale`, `maxScale`, `bobAmplitude`, `bobDuration`, `cascadeStep`).

- [ ] **Step 1: Failing test** — `WatcherConfigTests`: `test_default_satisfiesInvariant` asserts `WatcherConfig.default.liveWindow < .default.staleTimeout` and all values > 0; `test_invalidConfig_trapsInDebug` documents the precondition (use a comment + a valid-construction test, since `precondition` traps can't be XCTAssert'd portably — instead test a `validated()` returning `Result`/bool). Decision: expose `static func isValid(...) -> Bool` (pure, testable) AND call it from a `precondition` in `init`.

```swift
func test_default_isValid() {
    let c = WatcherConfig.default
    XCTAssertTrue(WatcherConfig.isValid(liveWindow: c.liveWindow, staleTimeout: c.staleTimeout,
                                        pollInterval: c.pollInterval, probeTimeout: c.probeTimeout,
                                        transcriptReadBytes: c.transcriptReadBytes))
}
func test_isValid_rejectsLiveWindowNotLessThanStale() {
    XCTAssertFalse(WatcherConfig.isValid(liveWindow: 90, staleTimeout: 90, pollInterval: 2,
                                         probeTimeout: 3, transcriptReadBytes: 65536))
}
```

- [ ] **Step 2: Run, verify fail** — `swift test --filter WatcherConfigTests` → fail (type not found).
- [ ] **Step 3: Implement** — `WatcherConfig` with `isValid` (liveWindow>0, staleTimeout>liveWindow, pollInterval>0, probeTimeout>0, transcriptReadBytes>=4096), `init` calling `precondition(Self.isValid(...))`, `static let default` (pollInterval 2, liveWindow 30, staleTimeout 90, probeTimeout 3, transcriptReadBytes 262144). Add `RenderConfig` with current literals (pixelScale 16, minScale 0.5, maxScale 3.0, bobAmplitude 3, bobDuration 0.7, cascadeStep 40).
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** — `feat(core): typed WatcherConfig/RenderConfig with validated invariants`.

## Task 2: `PathNormalizer.standardize` + `TranscriptDecoder.firstCWD(in:)` in Core

**Files:**
- Create: `Sources/AIMonCore/PathNormalizer.swift`
- Modify: `Sources/AIMonCore/TranscriptDecoder.swift`
- Test: `Tests/AIMonCoreTests/PathNormalizerTests.swift`, `Tests/AIMonCoreTests/TranscriptDecoderTests.swift` (extend)

**Interfaces:**
- Produces: `public enum PathNormalizer { static func standardize(_ path: String) -> String }` (`URL(fileURLWithPath:).resolvingSymlinksInPath().path`). `public extension TranscriptDecoder { static func firstCWD(in data: Data) -> String? }`.

- [ ] **Step 1: Failing tests** — `PathNormalizerTests.test_standardize_resolvesSymlink` (create temp symlink dir, assert standardize maps both to the same resolved path). `TranscriptDecoderTests.test_firstCWD_scansLineByLineAcrossMultibyteBoundary`:

```swift
func test_firstCWD_findsCwdEvenWhenAByteChunkWouldSplitAMultibyteChar() {
    // line 0 has a multibyte char and NO cwd; line 1 has the cwd.
    let l0 = #"{"type":"queue-operation","note":"café ☕"}"#
    let l1 = #"{"type":"user","sessionId":"s","cwd":"/Users/roman/Projects/aimon"}"#
    let data = Data((l0 + "\n" + l1 + "\n").utf8)
    XCTAssertEqual(TranscriptDecoder.firstCWD(in: data), "/Users/roman/Projects/aimon")
}
func test_firstCWD_nilWhenNoCwdPresent() {
    XCTAssertNil(TranscriptDecoder.firstCWD(in: Data(#"{"type":"queue-operation"}"#.utf8)))
}
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** — `firstCWD(in:)` splits `data` on the ASCII newline byte `0x0A` (line boundaries are always ASCII, so no decode is ever cut mid-multibyte-char), decodes each complete line to `String`, calls existing `meta(fromLine:)`, returns the first non-nil `cwd`. `PathNormalizer.standardize` as above.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** — `feat(core): pure path normalizer + line-by-line cwd extractor`.

## Task 3: `cwd` on `TranscriptFile` + `SessionRef` (additive)

**Files:**
- Modify: `Sources/AIMonCore/SessionWatch.swift`
- Create: `Sources/AIMonCore/SessionWatchEngine.swift` (types only this task)
- Test: `Tests/AIMonCoreTests/SessionRefTests.swift`

**Interfaces:**
- Produces: `TranscriptFile` gains `public let cwd: String?` with `init(sessionId:lastModified:cwd:String? = nil)` (default keeps existing call sites compiling). `public struct SessionRef: Equatable, Sendable { let sessionId: String; let cwd: String; let seed: UInt64 }`. `public struct WatchOutcome: Equatable { let started: [SessionRef]; let ended: [String] }`.

- [ ] **Step 1: Failing test** — `SessionRefTests.test_sessionRef_seedDerivesFromCwd` asserts `SessionRef(sessionId:"s", cwd:"/x", seed: ProjectIdentity.seed(forCWD:"/x")).seed == ProjectIdentity.seed(forCWD:"/x")` (trivial, but pins the type + Equatable/Sendable conformance and that consumers compute seed via `ProjectIdentity`).
- [ ] **Step 2: Run, verify fail** (types not found).
- [ ] **Step 3: Implement** — add `cwd` to `TranscriptFile` (Equatable still synthesized); add `SessionRef`, `WatchOutcome` in `SessionWatchEngine.swift`. Leave existing `WatcherReconciler`/`canSpawn` untouched (still used by the shell until Task 7).
- [ ] **Step 4: Run, verify pass** (`swift test` full — existing tests still green because `cwd` defaulted).
- [ ] **Step 5: Commit** — `feat(core): add cwd to TranscriptFile; SessionRef/WatchOutcome types`.

## Task 4: `SessionWatchEngine` — the unified top-P decision (the heart)

**Files:**
- Modify: `Sources/AIMonCore/SessionWatchEngine.swift`
- Test: `Tests/AIMonCoreTests/SessionWatchEngineTests.swift`

**Interfaces:**
- Consumes: `WatcherConfig` (Task 1), `SessionRef`/`WatchOutcome`/`TranscriptFile.cwd` (Task 3), `ProjectIdentity.seed`, `SessionLiveness`.
- Produces:
```swift
public final class SessionWatchEngine {
    public init(config: WatcherConfig)
    public private(set) var tracked: [SessionRef]            // for assertions/diagnostics
    /// Pure given its arguments; mutates internal tracked and returns the delta.
    public func step(files: [TranscriptFile], liveCWDs: [String]?, now: Date) -> WatchOutcome
}
```

**Decision rule (implement exactly):**
- Build `liveCWDCounts: [String:Int]?` from `liveCWDs` (`nil` stays `nil`; else tally).
- Partition input `files` into those with a usable `cwd` (skip `cwd == nil`).
- For the union of {currently-tracked sessions} ∪ {untracked files-with-cwd}, group by `cwd`.
- **Probe available (`counts != nil`)** — per cwd `C`: let `P = counts[C] ?? 0`. Rank all members at `C` (tracked + untracked candidates) by `(lastModified desc, sessionId asc)` for determinism, using the file's `lastModified` (a tracked session whose file vanished ranks last / is dropped). The **kept set** = the first `P` members. Then: `started` = kept members that were untracked; `ended` = tracked members not in the kept set (incl. vanished-file tracked).
- **Probe unavailable (`counts == nil`)** — degrade to mtime: `started` = untracked files where `SessionLiveness.isLive(mtime, now, config.liveWindow)`; `ended` = tracked whose file vanished OR `SessionLiveness.isEnded(mtime, now, config.staleTimeout)`.
- For each `started` file, build `SessionRef(sessionId:, cwd: file.cwd!, seed: ProjectIdentity.seed(forCWD: file.cwd!))`.
- Update `self.tracked` (remove ended, add started). Return `WatchOutcome(started: sorted-by-id, ended: sorted)`.

- [ ] **Step 1: Failing tests** — port the three regression scenarios + add resume, as **multi-tick scripted** sequences (this is the integration-level coverage the old code lacked):

```swift
// helpers: file(id, ageSec, cwd), step over a scripted clock
func test_idleSessionWithLiveProcess_isKept() { /* P=1, 1 stale-mtime tracked -> no end */ }
func test_ctrlC_endsThenStaysGone_noFlap() {
    // tick1: P=1 fresh -> started [s]; tick2: P=0, file still fresh -> ended [s];
    // tick3: P=0, file still fresh, untracked -> started [] (NO respawn)
}
func test_duplicateSibling_keepsFreshestEndsStalest() { /* P=1, 2 same-cwd -> end stalest */ }
func test_resume_staleMtimeButLiveProcess_spawns() {
    // tick1: untracked file age=9999 (resumed), P=1 (counts:[cwd:1]) -> started [s]
}
func test_twoFreshSameCwd_onlyOneProcess_spawnsExactlyOne() { /* P=1, 2 fresh untracked -> 1 started, freshest */ }
func test_twoProcessesTwoSessions_keepsBoth() { /* P=2 -> 2 started */ }
func test_probeNil_fallsBackToMtime() { /* liveCWDs nil: fresh->start, stale tracked->end */ }
func test_fileWithNilCwd_neverSpawns() { /* queue-op style: cwd nil -> ignored */ }
func test_startedRef_carriesCwdAndSeed() { /* started[0].seed == ProjectIdentity.seed(cwd) */ }
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement `step`** per the decision rule above.
- [ ] **Step 4: Run, verify pass** (`swift test --filter SessionWatchEngineTests`, then full suite).
- [ ] **Step 5: Commit** — `feat(core): SessionWatchEngine with unified top-P spawn/despawn decision`.

## Task 5: `ProcessScan.resolveLiveCWDs` tri-state combiner

**Files:**
- Modify: `Sources/AIMonCore/ProcessScan.swift`
- Test: `Tests/AIMonCoreTests/ProcessScanTests.swift` (extend)

**Interfaces:**
- Produces: `static func resolveLiveCWDs(claudePIDs: [String]?, lsofOutput: String?, lsofExitOK: Bool) -> [String]?`.

**Rule:** `claudePIDs == nil` (ps failed) → `nil`. `pids.isEmpty` → `[]` (no claude running; legitimate). `lsofOutput == nil || !lsofExitOK` → `nil`. Parse `cwds(fromLSOF:)`; if `cwds.count != pids.count` (lsof dropped a since-dead pid → undercount) → `nil`. Else `cwds`.

- [ ] **Step 1: Failing tests** — 4-case table + undercount:
```swift
func test_resolve_psFailed_isNil() { XCTAssertNil(ProcessScan.resolveLiveCWDs(claudePIDs: nil, lsofOutput: "n/x\n", lsofExitOK: true)) }
func test_resolve_noClaude_isEmpty() { XCTAssertEqual(ProcessScan.resolveLiveCWDs(claudePIDs: [], lsofOutput: nil, lsofExitOK: false), []) }
func test_resolve_lsofFailed_isNil() { XCTAssertNil(ProcessScan.resolveLiveCWDs(claudePIDs: ["1"], lsofOutput: nil, lsofExitOK: false)) }
func test_resolve_lsofUndercount_isNil() {
    XCTAssertNil(ProcessScan.resolveLiveCWDs(claudePIDs: ["1","2"], lsofOutput: "p1\nn/x\n", lsofExitOK: true))
}
func test_resolve_success_returnsCwds() {
    XCTAssertEqual(ProcessScan.resolveLiveCWDs(claudePIDs: ["1","2"], lsofOutput: "p1\nn/x\np2\nn/y\n", lsofExitOK: true), ["/x","/y"])
}
```
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** — `fix(core): tri-state live-cwd resolution guards against lsof undercount`.

## Task 6: `FileTranscriptStore` — real FS store, testable via temp dirs

**Files:**
- Create: `Sources/AIMonCore/FileTranscriptStore.swift`
- Test: `Tests/AIMonCoreTests/FileTranscriptStoreTests.swift`

**Interfaces:**
- Produces:
```swift
public protocol TranscriptStore { func scan() -> [TranscriptFile]? }   // nil == enumeration FAILED (≠ empty)
public protocol Clock { func now() -> Date }
public struct SystemClock: Clock { public func now() -> Date }
public final class FileTranscriptStore: TranscriptStore {
    public init(projectsRoot: URL, config: WatcherConfig)
    public func scan() -> [TranscriptFile]?   // each file: sessionId, mtime, cwd (cached; resolved once via firstCWD)
}
```
**Behavior:** enumerate `projectsRoot/*/*.jsonl`; for each, sessionId = filename stem, mtime via `contentModificationDateKey`; `cwd` = cached, else read up to `config.transcriptReadBytes`, `TranscriptDecoder.firstCWD(in:)`, then `PathNormalizer.standardize`; cache by sessionId. Return `nil` if the top-level `projectsRoot` enumeration THROWS (vs returns empty). Per-subdir/file errors → skip that entry (logged by caller later).

- [ ] **Step 1: Failing tests** — temp-dir harness:
```swift
func test_scan_discoversTranscriptsWithMtimeAndCwd() { /* write project dir + a.jsonl with cwd line; assert one TranscriptFile, cwd standardized */ }
func test_scan_missingRoot_returnsNil() { /* nonexistent projectsRoot -> nil (NOT []) */ }
func test_scan_emptyRoot_returnsEmpty() { /* existing empty dir -> [] */ }
func test_scan_transcriptWithoutCwd_hasNilCwd() { /* queue-op-only file -> cwd nil */ }
func test_scan_cwdResolvedThroughSymlink_matchesStandardized() { /* cwd line points at /tmp symlink; assert standardized == resolved */ }
```
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** — `feat(core): FileTranscriptStore with cwd caching + temp-dir tests`.

## Task 7: Rewrite the shell — off-main timeout probe, `@MainActor`, engine wiring (delete old reconciler)

**Files:**
- Create: `Sources/AIMon/ProcessProbeCLI.swift`
- Modify: `Sources/AIMon/TranscriptWatcher.swift`, `Sources/AIMon/AppDelegate.swift`
- Modify: `Sources/AIMonCore/SessionWatch.swift` (DELETE `WatcherReconciler.reconcile`/`canSpawn`), delete `Tests/AIMonCoreTests/WatcherReconcilerTests.swift`
- Verify: build + **live run** (no unit test for the shell)

**Interfaces:**
- Consumes: `SessionWatchEngine`, `FileTranscriptStore`, `WatchOutcome`, `WatcherConfig`, `ProcessScan.{claudePIDs,resolveLiveCWDs}`.
- Produces: `final class ProcessProbeCLI: ProcessProbe { func liveCWDs() -> [String]? }` (synchronous, intended to be called on a background queue), running `/bin/ps` then `/usr/sbin/lsof` each via a `run(_:_:timeout:) -> (output:String, exitOK:Bool)?` that drains stdout on a concurrent reader and kills the process on `config.probeTimeout`. `protocol ProcessProbe { func liveCWDs() -> [String]? }` (define in Core alongside the engine protocols).

**Threading contract (write this as a comment block in TranscriptWatcher):**
- `@MainActor`: `AppDelegate`, `CompanionWindow`, `TranscriptWatcher` (the engine + windows + tracked all mutate on main only).
- Background serial `DispatchQueue(label: "io.romanc.aimon.probe", qos: .utility)`: `store.scan()` + `probe.liveCWDs()` only. Returns Sendable value types (`[TranscriptFile]?`, `[String]?`, `Date`).
- Each tick: if `isProbing` (main-only flag) skip; else set it, dispatch IO to the bg queue, hop back to main, clear flag, run `engine.step(...)`, apply `WatchOutcome` to windows. Timer stays in `.common` mode (liveness keeps updating during drags/menus; only the blocking work left main).

- [ ] **Step 1: `ProcessProbeCLI.run` with timeout** — implement the concurrent-read + `terminationHandler`-semaphore + `terminate()`-on-deadline runner; `liveCWDs()` = `claudePIDs(fromPS:)` → `resolveLiveCWDs(...)`. (No unit test; correctness of parsing/tri-state already covered in Tasks 4–5.)
- [ ] **Step 2: Rewrite `TranscriptWatcher`** to hold `SessionWatchEngine` + injected `TranscriptStore`/`ProcessProbe`/`Clock` (defaults: `FileTranscriptStore`, `ProcessProbeCLI`, `SystemClock`); implement the off-main tick; expose `var onOutcome: ((WatchOutcome) -> Void)?` (replacing `onStarted`/`onEnded`). Mark `@MainActor`.
- [ ] **Step 3: Update `AppDelegate`** — `@MainActor`; route `onOutcome` → spawn each `started` `SessionRef` (seed already on the ref; restore `lastFrameBySeed` else cascade), despawn each `ended` id. Keep `sessionWindows: [String: CompanionWindow]`, `seedBySession`, `lastFrameBySeed` (per-project position memory stays seed-keyed). Remove the now-dead `tracked/sessionWindows` desync guard.
- [ ] **Step 4: Delete** `WatcherReconciler.reconcile`/`canSpawn` from `SessionWatch.swift` and delete `WatcherReconcilerTests.swift` (superseded by `SessionWatchEngineTests`). Keep `TranscriptFile`/`TrackedSession`? — `TrackedSession` is now unused; delete it.
- [ ] **Step 5: Build + full test suite green.** `swift build && swift test`.
- [ ] **Step 6: LIVE verification (assistant-run, per project convention):** kill any running AIMon, launch the rebuilt binary in the background, and confirm via lifecycle logs against the live system: (a) exactly one spawn for the current session; (b) a throwaway `claude -p` session spawns once and despawns within ~one poll after exit, no flap; (c) the app stays responsive (no main-thread block — verify by reading logs show ticks continuing). Document results in the commit.
- [ ] **Step 7: Commit** — `refactor: extract pure SessionWatchEngine; off-main timeout probe; @MainActor shell`.

## Task 8: Observability — `os.Logger` spine + observable degradation

**Files:**
- Create: `Sources/AIMon/Log.swift`
- Modify: `Sources/AIMon/TranscriptWatcher.swift`, `AppDelegate.swift`, `Sources/AIMonCore/FileTranscriptStore.swift` (return reason on cwd-miss)
- Verify: build + live log inspection

**Interfaces:**
- Produces: `enum Log { static let watcher: Logger; static let lifecycle: Logger }` (subsystem `io.romanc.aimon`).

- [ ] **Step 1:** Add `os.Logger` instances. Replace the two `NSLog` lifecycle lines with `Log.lifecycle.info(...)` (spawn/despawn with sessionId prefix + `live` count).
- [ ] **Step 2:** Log per-tick **inputs** at `.debug`: file count, `live-cwd counts` or `"probe-down"`, and the resulting `started`/`ended`. Log probe `available→nil` / `nil→available` transitions at `.notice` (rate-limited), naming which command failed.
- [ ] **Step 3:** Make cwd-miss observable: when `FileTranscriptStore` can't resolve a cwd for a file that the engine would otherwise consider, log at `.debug` with a reason (open-failed / decode-failed / no-cwd). Distinguish FS-enumeration failure (`scan()==nil`, log `.error`, **skip the tick** — never mass-despawn on a transient FS hiccup) from empty (`[]`).
- [ ] **Step 4:** Privacy: log cwd with `privacy: .public` ONLY behind a debug build flag; default redact (`privacy: .private`). sessionId prefixes are non-sensitive (`.public`).
- [ ] **Step 5: Build + live:** launch, confirm `log stream --predicate 'subsystem == "io.romanc.aimon"'` shows tick inputs and lifecycle events; verify a `nil` scan (rename projectsRoot mid-run is overkill — instead unit-confirmed in Task 6) does not despawn.
- [ ] **Step 6: Commit** — `feat: os.Logger spine; log decision inputs and silent-drop branches`.

## Task 9: Lifecycle hygiene + config wiring + cleanup

**Files:**
- Modify: `Sources/AIMon/CompanionWindow.swift`, `CompanionScene.swift`, `AppDelegate.swift`

- [ ] **Step 1:** `CompanionWindow`/`CompanionScene`: add `deinit { Log.lifecycle.debug("…released") }` (makes ownership observable; a future M4 retain cycle becomes visible immediately). Set `isReleasedWhenClosed = false` on the panel (dictionary is the single owner).
- [ ] **Step 2:** `CompanionScene.init` failable (`init?`) — return `nil` instead of `fatalError` when the sprite image can't build; the spawn path skips + logs that one session (one bad sprite must not crash the whole app). Wire `RenderConfig` sizing constants (pixelScale, bob, scale bounds) instead of literals.
- [ ] **Step 3:** `AppDelegate.applicationWillTerminate` — `watcher.stop()`, close all windows. (Becomes the required cancellation hook for M4 Brain/Speech resources.)
- [ ] **Step 4:** Dev-spawn: add a `"Despawn dev monsters"` menu item that clears `devCompanions`; keep the affordance but ensure it never touches the reconcile invariant (it already lives in a separate array).
- [ ] **Step 5: Build + test green; brief live sanity (deinit logs fire on despawn).**
- [ ] **Step 6: Commit** — `chore: lifecycle hygiene, failable scene init, RenderConfig wiring, termination teardown`.

---

## Self-Review

**Spec/review coverage:** rank 1 → Task 7 (off-main+timeout) + Task 7 threading contract; rank 2 (resume) → Task 4 (`test_resume_…`); rank 3 (engine extraction + cwd on model) → Tasks 3,4,6,7; rank 4 (event shape) → partial: `WatchOutcome`/`SessionRef` are the minimal `started/ended` seed of the full `SessionEvent` stream (full activity vocabulary deferred to M4 with its Brain consumer, per the review's explicit recommendation); rank 5 (rich decoder/classifier/tailing) → **deferred to M4** (only `firstCWD` line-scan + read-cap bump done here, Task 2); rank 6 (concurrency contract) → Task 7 (`@MainActor` + bg-queue rule); rank 7 (render state/bubble) → **deferred to M4**; rank 8 (logging) → Task 8; rank 9 (cwd 64KB/multibyte) → Task 2; rank 10 (probe tri-state) → Task 5; rank 11 (FS harness) → Task 6; rank 12 (lifecycle) → Task 9; rank 13 (config/failable/dead-guard) → Tasks 1,9,7.

**Deferred to M4 (intentional, not gaps):** the rich `SessionEvent` activity enum + `ActivityClassifier` + offset-tailing reader (rank 5), and the state-aware `AppearanceProvider`/render `setState`+speech-bubble (rank 7). Rationale (from the verified review): these must be shaped together with the Brain that consumes them; building them now risks designing the event vocabulary in a vacuum. The engine's `WatchOutcome.started/ended` + `SessionRef` is deliberately the minimal forward-compatible seed.

**Type consistency:** `WatchOutcome{started:[SessionRef], ended:[String]}` produced in Task 3, implemented in Task 4, consumed in Task 7. `TranscriptStore.scan() -> [TranscriptFile]?` (Task 6) consumed in Task 7. `ProcessProbe.liveCWDs() -> [String]?` defined Task 6/7, implemented `ProcessProbeCLI` Task 7. `WatcherConfig` (Task 1) threaded through Tasks 4,6,7,9. `firstCWD(in:)`/`standardize` (Task 2) used by `FileTranscriptStore` (Task 6). No dangling references.

**Placeholder scan:** decision rules and test names are concrete; the trickiest code (engine `step`, timeout runner) has its algorithm spelled out step-by-step rather than as a code dump, because it will be TDD'd against the listed tests during execution.
