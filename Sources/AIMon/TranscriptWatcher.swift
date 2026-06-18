import Foundation
import AIMonCore

/// Thin impure shell around the pure `SessionWatchEngine`.
///
/// **Threading contract** (the safety here is queue confinement, not the compiler — full
/// `@MainActor`/`Sendable` annotations arrive with the deliberate Swift-6 tools bump):
///  - A `Timer` on `RunLoop.main` (`.common` mode, so liveness keeps updating during drags
///    and menu tracking) fires each tick on the **main thread**.
///  - The filesystem scan (`store.scan()`) and the `ps`/`lsof` probe (`probe.liveCWDs()`) —
///    the only blocking I/O — run on a **background serial queue**. A hung probe can never
///    freeze the UI.
///  - The engine decision and `onOutcome` delivery happen back on the **main thread**.
///  - `engine`/`isProbing` are touched only on main; `store`/`probe` only on `probeQueue`.
///    `isProbing` skips overlapping ticks so a slow probe can't pile up.
final class TranscriptWatcher {
    /// Delivered on the main thread whenever a tick changes the live set.
    var onOutcome: ((WatchOutcome) -> Void)?

    private let engine: SessionWatchEngine
    private let store: TranscriptStore
    private let probe: ProcessProbe
    private let clock: Clock
    private let config: WatcherConfig

    private let probeQueue = DispatchQueue(label: "io.romanc.aimon.probe", qos: .utility)
    private var timer: Timer?
    private var isProbing = false
    private var lastProbeAvailable: Bool?   // for logging probe up/down transitions

    init(projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
         config: WatcherConfig = .default,
         store: TranscriptStore? = nil,
         probe: ProcessProbe? = nil,
         clock: Clock = SystemClock()) {
        self.config = config
        self.engine = SessionWatchEngine(config: config)
        self.store = store ?? FileTranscriptStore(projectsRoot: projectsRoot, config: config)
        self.probe = probe ?? ProcessProbeCLI(config: config)
        self.clock = clock
    }

    func start() {
        let t = Timer(timeInterval: config.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Tick (main → background I/O → main)

    private func tick() {
        guard !isProbing else { return }
        isProbing = true
        let store = self.store
        let probe = self.probe
        let now = clock.now()
        probeQueue.async { [weak self] in
            let files = store.scan()
            let live = probe.liveCWDs()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isProbing = false
                guard let files = files else {
                    Log.watcher.error("transcript scan failed; skipping tick (no despawn)")
                    return                                // scan failed → skip tick, never mass-despawn
                }
                let available = live != nil
                if available != self.lastProbeAvailable {
                    Log.watcher.notice("process probe \(available ? "available" : "unavailable")")
                    self.lastProbeAvailable = available
                }
                let outcome = self.engine.step(files: files, liveCWDs: live, now: now)
                let liveDesc = live == nil ? "down" : String(live!.count)
                Log.watcher.debug("tick files=\(files.count) live=\(liveDesc) started=\(outcome.started.count) ended=\(outcome.ended.count)")
                if !outcome.started.isEmpty || !outcome.ended.isEmpty {
                    self.onOutcome?(outcome)
                }
            }
        }
    }
}
