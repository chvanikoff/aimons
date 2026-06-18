# Session Watcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect live Claude Code sessions by watching `~/.claude/projects/**/*.jsonl` and spawn one floating monster per live session (despawning when the session ends), with each project getting a deterministic, persistent-looking creature.

**Architecture:** Pure, unit-tested logic in `AIMonCore` — a deterministic project→seed hash, a tolerant JSONL line decoder (`sessionId` + `cwd`), a liveness/stale judge, and a pure `WatcherReconciler` that diffs the current file set against tracked sessions into start/end decisions. A thin, impure `TranscriptWatcher` in the `AIMon` executable polls the filesystem (every ~2s) and applies those decisions via callbacks; `AppDelegate` maps them to `CompanionWindow` spawn/despawn. Implements Milestone 3 (baseline session tracking) of `docs/superpowers/specs/2026-06-18-aimon-companion-design.md`. Rich activity classification and speech are deferred to the Brain milestone (M4), so this plan extracts only `sessionId`/`cwd` from transcripts.

**Tech Stack:** Swift 5.9+ (SwiftPM, Swift-5 language mode), Foundation (`JSONSerialization`, `FileManager`, `Timer`, `Date`), AppKit. macOS 13+. Builds on the existing `AIMonCore` library and `AIMon` executable.

**Conventions for the executor:**
- Run `swift build` / `swift test` from the repo root (`/Users/roman/Projects/aimon`).
- TDD applies to all `AIMonCore` work (Tasks 1–4). The watcher (Task 5) is build-verified; integration (Task 6) ends with a **manual run check you perform**, since GUI + live-session behaviour can't be tested headlessly.
- Polling (not FSEvents) is an intentional v1 choice: simpler and robust; FSEvents is a possible later optimization. (Spec §6 mentions FSEvents; this is a documented deviation.)
- Every commit message ends with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- Work happens on branch `feature/session-watcher`.

---

### Task 1: Deterministic project → seed

Same working directory must always yield the same monster (FNV-1a 64-bit hash).

**Files:**
- Create: `Sources/AIMonCore/ProjectIdentity.swift`
- Test: `Tests/AIMonCoreTests/ProjectIdentityTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AIMonCoreTests/ProjectIdentityTests.swift`:

```swift
import XCTest
@testable import AIMonCore

final class ProjectIdentityTests: XCTestCase {
    func test_sameCWD_producesSameSeed() {
        let a = ProjectIdentity.seed(forCWD: "/Users/roman/Projects/aimon")
        let b = ProjectIdentity.seed(forCWD: "/Users/roman/Projects/aimon")
        XCTAssertEqual(a, b)
    }

    func test_differentCWDs_produceDifferentSeeds() {
        let a = ProjectIdentity.seed(forCWD: "/Users/roman/Projects/aimon")
        let b = ProjectIdentity.seed(forCWD: "/Users/roman/Projects/other")
        XCTAssertNotEqual(a, b)
    }

    func test_emptyString_isStableNonCrashing() {
        XCTAssertEqual(ProjectIdentity.seed(forCWD: ""), ProjectIdentity.seed(forCWD: ""))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProjectIdentityTests`
Expected: FAIL — `cannot find 'ProjectIdentity' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AIMonCore/ProjectIdentity.swift`:

```swift
/// Maps a project working directory to a stable monster seed, so the same project
/// always shows the same creature. FNV-1a 64-bit hash of the UTF-8 path.
public enum ProjectIdentity {
    public static func seed(forCWD cwd: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325   // FNV offset basis
        for byte in cwd.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3    // FNV prime
        }
        return hash
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProjectIdentityTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AIMonCore/ProjectIdentity.swift Tests/AIMonCoreTests/ProjectIdentityTests.swift
git commit -m "$(printf 'feat(core): deterministic project->seed hash\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 2: Tolerant transcript line decoder

Extract just `sessionId` and `cwd` from a JSONL line. Must tolerate blank/garbage lines and lines without `cwd` (e.g. `ai-title`, `last-prompt`).

**Files:**
- Create: `Sources/AIMonCore/TranscriptDecoder.swift`
- Test: `Tests/AIMonCoreTests/TranscriptDecoderTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AIMonCoreTests/TranscriptDecoderTests.swift` (fixtures mirror the real schema observed on disk):

```swift
import XCTest
@testable import AIMonCore

final class TranscriptDecoderTests: XCTestCase {
    func test_userLine_extractsSessionIdAndCWD() {
        let line = #"{"type":"user","sessionId":"abc-123","cwd":"/Users/roman/Projects/aimon","timestamp":"2026-06-18T15:00:00Z","message":{"role":"user","content":"hi"},"gitBranch":"main"}"#
        let meta = TranscriptDecoder.meta(fromLine: line)
        XCTAssertEqual(meta?.sessionId, "abc-123")
        XCTAssertEqual(meta?.cwd, "/Users/roman/Projects/aimon")
    }

    func test_titleLine_hasSessionIdButNoCWD() {
        let line = #"{"type":"ai-title","sessionId":"abc-123","aiTitle":"Some title"}"#
        let meta = TranscriptDecoder.meta(fromLine: line)
        XCTAssertEqual(meta?.sessionId, "abc-123")
        XCTAssertNil(meta?.cwd)
    }

    func test_blankLine_isNil() {
        XCTAssertNil(TranscriptDecoder.meta(fromLine: ""))
        XCTAssertNil(TranscriptDecoder.meta(fromLine: "   "))
    }

    func test_garbageLine_isNil() {
        XCTAssertNil(TranscriptDecoder.meta(fromLine: "not json at all"))
    }

    func test_objectWithoutSessionId_isNil() {
        XCTAssertNil(TranscriptDecoder.meta(fromLine: #"{"type":"summary"}"#))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TranscriptDecoderTests`
Expected: FAIL — `cannot find 'TranscriptDecoder' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AIMonCore/TranscriptDecoder.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TranscriptDecoderTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AIMonCore/TranscriptDecoder.swift Tests/AIMonCoreTests/TranscriptDecoderTests.swift
git commit -m "$(printf 'feat(core): tolerant transcript line decoder (sessionId, cwd)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 3: Session liveness judge

Pure time-threshold logic: a transcript is "live" if modified recently; a tracked session has "ended" if stale.

**Files:**
- Create: `Sources/AIMonCore/SessionLiveness.swift`
- Test: `Tests/AIMonCoreTests/SessionLivenessTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AIMonCoreTests/SessionLivenessTests.swift`:

```swift
import XCTest
import Foundation
@testable import AIMonCore

final class SessionLivenessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_isLive_trueWithinWindow() {
        let modified = now.addingTimeInterval(-10)
        XCTAssertTrue(SessionLiveness.isLive(lastModified: modified, now: now, liveWindow: 30))
    }

    func test_isLive_falseBeyondWindow() {
        let modified = now.addingTimeInterval(-60)
        XCTAssertFalse(SessionLiveness.isLive(lastModified: modified, now: now, liveWindow: 30))
    }

    func test_isEnded_falseWithinTimeout() {
        let modified = now.addingTimeInterval(-30)
        XCTAssertFalse(SessionLiveness.isEnded(lastModified: modified, now: now, staleTimeout: 90))
    }

    func test_isEnded_trueBeyondTimeout() {
        let modified = now.addingTimeInterval(-120)
        XCTAssertTrue(SessionLiveness.isEnded(lastModified: modified, now: now, staleTimeout: 90))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionLivenessTests`
Expected: FAIL — `cannot find 'SessionLiveness' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AIMonCore/SessionLiveness.swift`:

```swift
import Foundation

/// Time-based judgement of whether a transcript represents an active session.
public enum SessionLiveness {
    /// A transcript is "live" if it was modified within `liveWindow` seconds of `now`.
    public static func isLive(lastModified: Date, now: Date, liveWindow: TimeInterval) -> Bool {
        now.timeIntervalSince(lastModified) <= liveWindow
    }

    /// A tracked session has "ended" if its transcript has been stale longer than `staleTimeout`.
    public static func isEnded(lastModified: Date, now: Date, staleTimeout: TimeInterval) -> Bool {
        now.timeIntervalSince(lastModified) > staleTimeout
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SessionLivenessTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/AIMonCore/SessionLiveness.swift Tests/AIMonCoreTests/SessionLivenessTests.swift
git commit -m "$(printf 'feat(core): session liveness/stale judge\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 4: Watcher reconciler (pure diff)

Given the current transcript files and the set of already-tracked sessions, decide which sessions to start and which to end. This is the testable heart of the watcher.

**Files:**
- Create: `Sources/AIMonCore/SessionWatch.swift`
- Test: `Tests/AIMonCoreTests/WatcherReconcilerTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AIMonCoreTests/WatcherReconcilerTests.swift`:

```swift
import XCTest
import Foundation
@testable import AIMonCore

final class WatcherReconcilerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func file(_ id: String, ageSeconds: TimeInterval) -> TranscriptFile {
        TranscriptFile(sessionId: id, lastModified: now.addingTimeInterval(-ageSeconds))
    }

    func test_newLiveFile_isStarted() {
        let d = WatcherReconciler.reconcile(files: [file("s1", ageSeconds: 5)],
                                            tracked: [], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toStart, ["s1"])
        XCTAssertEqual(d.toEnd, [])
    }

    func test_staleFile_notTracked_isIgnored() {
        let d = WatcherReconciler.reconcile(files: [file("old", ageSeconds: 9999)],
                                            tracked: [], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toStart, [])
        XCTAssertEqual(d.toEnd, [])
    }

    func test_trackedFreshFile_isNotEnded() {
        let d = WatcherReconciler.reconcile(files: [file("s1", ageSeconds: 10)],
                                            tracked: ["s1"], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toStart, [])
        XCTAssertEqual(d.toEnd, [])
    }

    func test_trackedStaleFile_isEnded() {
        let d = WatcherReconciler.reconcile(files: [file("s1", ageSeconds: 200)],
                                            tracked: ["s1"], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toEnd, ["s1"])
    }

    func test_trackedFileVanished_isEnded() {
        let d = WatcherReconciler.reconcile(files: [],
                                            tracked: ["gone"], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toEnd, ["gone"])
    }

    func test_alreadyTrackedLiveFile_isNotStartedAgain() {
        let d = WatcherReconciler.reconcile(files: [file("s1", ageSeconds: 5)],
                                            tracked: ["s1"], now: now,
                                            liveWindow: 30, staleTimeout: 90)
        XCTAssertEqual(d.toStart, [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WatcherReconcilerTests`
Expected: FAIL — `cannot find 'TranscriptFile' / 'WatcherReconciler' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/AIMonCore/SessionWatch.swift`:

```swift
import Foundation

/// A transcript file as seen by the watcher: its session id and last-modified time.
public struct TranscriptFile: Equatable {
    public let sessionId: String
    public let lastModified: Date

    public init(sessionId: String, lastModified: Date) {
        self.sessionId = sessionId
        self.lastModified = lastModified
    }
}

/// What the watcher should do this tick.
public struct WatchDecision: Equatable {
    public let toStart: [String]   // session ids newly live
    public let toEnd: [String]     // tracked session ids now ended

    public init(toStart: [String], toEnd: [String]) {
        self.toStart = toStart
        self.toEnd = toEnd
    }
}

public enum WatcherReconciler {
    /// Diffs `files` against `tracked` into start/end decisions. Results are sorted for
    /// determinism. A tracked session ends when its file is stale or has disappeared.
    public static func reconcile(files: [TranscriptFile],
                                 tracked: Set<String>,
                                 now: Date,
                                 liveWindow: TimeInterval,
                                 staleTimeout: TimeInterval) -> WatchDecision {
        var toStart: [String] = []
        var toEnd: [String] = []
        let byId = Dictionary(files.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })

        for f in files where !tracked.contains(f.sessionId) {
            if SessionLiveness.isLive(lastModified: f.lastModified, now: now, liveWindow: liveWindow) {
                toStart.append(f.sessionId)
            }
        }
        for id in tracked {
            if let f = byId[id] {
                if SessionLiveness.isEnded(lastModified: f.lastModified, now: now, staleTimeout: staleTimeout) {
                    toEnd.append(id)
                }
            } else {
                toEnd.append(id)   // file disappeared
            }
        }
        return WatchDecision(toStart: toStart.sorted(), toEnd: toEnd.sorted())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WatcherReconcilerTests`
Expected: PASS (6 tests). Then run the full suite: `swift test` → all green.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIMonCore/SessionWatch.swift Tests/AIMonCoreTests/WatcherReconcilerTests.swift
git commit -m "$(printf 'feat(core): pure watcher reconciler (start/end diff)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 5: TranscriptWatcher (polling, executable)

Impure glue: poll the projects directory, build `[TranscriptFile]`, run the reconciler, read `cwd` for newly-started sessions, and emit callbacks. Build-verified (no unit test — filesystem + timer).

**Files:**
- Create: `Sources/AIMon/TranscriptWatcher.swift`

- [ ] **Step 1: Write the watcher**

`Sources/AIMon/TranscriptWatcher.swift`:

```swift
import Foundation
import AIMonCore

/// Polls ~/.claude/projects for live Claude Code session transcripts and reports
/// session start/end. Polling (not FSEvents) is intentional for v1: simple and robust.
final class TranscriptWatcher {
    struct StartedSession {
        let sessionId: String
        let cwd: String
        let projectSeed: UInt64
    }

    var onStarted: ((StartedSession) -> Void)?
    var onEnded: ((String) -> Void)?

    private let projectsRoot: URL
    private let pollInterval: TimeInterval
    private let liveWindow: TimeInterval
    private let staleTimeout: TimeInterval

    private var tracked: Set<String> = []
    private var urlBySession: [String: URL] = [:]
    private var timer: Timer?

    init(projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
         pollInterval: TimeInterval = 2,
         liveWindow: TimeInterval = 30,
         staleTimeout: TimeInterval = 90) {
        self.projectsRoot = projectsRoot
        self.pollInterval = pollInterval
        self.liveWindow = liveWindow
        self.staleTimeout = staleTimeout
    }

    func start() {
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)   // keep ticking during menu tracking / drags
        self.timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let files = scanFiles()
        let decision = WatcherReconciler.reconcile(
            files: files, tracked: tracked, now: Date(),
            liveWindow: liveWindow, staleTimeout: staleTimeout)

        for id in decision.toStart {
            guard let url = urlBySession[id], let cwd = cwdFromFile(url) else { continue }
            tracked.insert(id)
            let seed = ProjectIdentity.seed(forCWD: cwd)
            onStarted?(StartedSession(sessionId: id, cwd: cwd, projectSeed: seed))
        }
        for id in decision.toEnd {
            tracked.remove(id)
            onEnded?(id)
        }
    }

    /// Enumerate ~/.claude/projects/*/*.jsonl, recording each session's mtime and URL.
    private func scanFiles() -> [TranscriptFile] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var result: [TranscriptFile] = []
        var urls: [String: URL] = [:]
        for dir in projectDirs {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for url in entries where url.pathExtension == "jsonl" {
                let sessionId = url.deletingPathExtension().lastPathComponent
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date.distantPast
                result.append(TranscriptFile(sessionId: sessionId, lastModified: mtime))
                urls[sessionId] = url
            }
        }
        urlBySession = urls
        return result
    }

    /// Read the first 64 KB of a transcript and return the first cwd found.
    private func cwdFromFile(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = handle.readData(ofLength: 64 * 1024)
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            if let meta = TranscriptDecoder.meta(fromLine: String(line)), let cwd = meta.cwd {
                return cwd
            }
        }
        return nil
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/AIMon/TranscriptWatcher.swift
git commit -m "$(printf 'feat: polling transcript watcher for live sessions\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 6: Wire sessions to monster spawn/despawn

Replace launch auto-spawn with session-driven spawning. Keep the dev "Spawn random monster" item.

**Files:**
- Modify: `Sources/AIMon/AppDelegate.swift`

- [ ] **Step 1: Replace `AppDelegate.swift` with the session-driven version**

Overwrite `Sources/AIMon/AppDelegate.swift` with:

```swift
import AppKit
import AIMonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let appearance: AppearanceProvider = ProceduralAppearance()
    private let watcher = TranscriptWatcher()

    private var sessionWindows: [String: CompanionWindow] = [:]   // sessionId -> window
    private var devCompanions: [CompanionWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusItem.button(in: NSStatusBar.system)
        item.button?.title = "👾"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "AIMon (preview)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Spawn random monster (dev)",
                                action: #selector(spawnDevMonster),
                                keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item

        watcher.onStarted = { [weak self] session in self?.handleSessionStarted(session) }
        watcher.onEnded = { [weak self] sessionId in self?.handleSessionEnded(sessionId) }
        watcher.start()
    }

    // MARK: - Session-driven windows

    private func handleSessionStarted(_ session: TranscriptWatcher.StartedSession) {
        guard sessionWindows[session.sessionId] == nil else { return }
        let window = CompanionWindow(seed: session.projectSeed, appearance: appearance)
        cascade(window, index: sessionWindows.count)
        window.orderFrontRegardless()
        sessionWindows[session.sessionId] = window
    }

    private func handleSessionEnded(_ sessionId: String) {
        sessionWindows[sessionId]?.close()
        sessionWindows[sessionId] = nil
    }

    // MARK: - Dev affordance

    @objc private func spawnDevMonster() {
        let seed = UInt64.random(in: 0..<UInt64.max)
        let window = CompanionWindow(seed: seed, appearance: appearance)
        cascade(window, index: devCompanions.count)
        window.orderFrontRegardless()
        devCompanions.append(window)
    }

    private func cascade(_ window: CompanionWindow, index: Int) {
        let step = CGFloat(index % 6) * 40
        var origin = window.frame.origin
        origin.x += step
        origin.y -= step
        window.setFrameOrigin(origin)
    }
}

private extension NSStatusItem {
    static func button(in bar: NSStatusBar) -> NSStatusItem {
        bar.statusItem(withLength: NSStatusItem.variableLength)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: MANUAL RUN CHECK (user)**

Run: `swift run AIMon`
Expected:
- Within ~2 seconds, a monster appears for **this live Claude Code session** (the `aimon` project), with no monster shown for the 100+ historical/inactive transcripts.
- Opening a Claude Code session in a *different* folder makes a *second*, different-looking monster appear within ~2s.
- Quitting a Claude Code session makes its monster disappear after the stale timeout (~90s). (Precise despawn arrives with the optional hooks tier later.)
- Re-opening a session in the same project shows the same-looking creature (deterministic per-project seed).
- "👾 → Spawn random monster (dev)" still adds extra monsters on demand.

- [ ] **Step 4: Commit**

```bash
git add Sources/AIMon/AppDelegate.swift
git commit -m "$(printf 'feat: spawn/despawn a monster per live Claude Code session\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Done criteria

`swift run AIMon` shows a monster for each *live* Claude Code session (one per session, deterministic per project), spawning within ~2s of a session becoming active and despawning when it goes stale — all driven by a unit-tested core (`swift test` green) and a thin polling watcher.

## Not in this plan (future plans)
- Rich activity classification (editing/running/reading/waiting) and the Companion Brain state machine (M4).
- Speech engine (Ollama/external/templates) + bubbles (M4).
- Persistent AIMon Registry: named, reassignable stable of monsters (currently identity is a deterministic per-project seed, not a stored/editable record).
- Optional hooks tier for precise lifecycle + instant despawn.
- FSEvents instead of polling (optimization).
- Corner drag-leak fix (tracked separately).
