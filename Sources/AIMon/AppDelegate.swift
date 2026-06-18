import AppKit
import AIMonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var visibilityItem: NSMenuItem?
    private let appearance: AppearanceProvider = ProceduralAppearance()
    private let watcher = TranscriptWatcher()

    private let speechEngine = SpeechEngine()
    private let registry = AIMonRegistry()
    private let focuser = SessionFocuser()

    private var projectWindows: [String: CompanionWindow] = [:]   // cwd -> window (one monster per project)
    private var sessionCountByCwd: [String: Int] = [:]           // cwd -> last seen live session count
    private var lastSpokeByCwd: [String: Date] = [:]            // cwd -> last time the monster spoke (cadence)
    private var personalityByCwd: [String: Personality] = [:]    // cwd -> personality (from registry, cached)
    private var devCompanions: [CompanionWindow] = []
    private var aimonsVisible = true
    private let speechCooldown: TimeInterval = 4
    private var nextIdleAt: [String: Date] = [:]   // cwd -> when the next idle thought is due
    private var idleTimer: Timer?
    private var didInitialApply = false            // suppress greetings for sessions already live at launch

    private let activityReader = TranscriptActivityReader()
    private let activityQueue = DispatchQueue(label: "io.romanc.aimon.activity", qos: .utility)
    private var activityTimer: Timer?
    private var activityProbing = false
    private var lastActivityByCwd: [String: SessionActivity] = [:]   // speak only when it changes

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusItem.button(in: NSStatusBar.system)
        item.button?.title = "👾"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "AIMon (preview)", action: nil, keyEquivalent: ""))
        let visItem = NSMenuItem(title: "Show AIMons", action: #selector(toggleVisibility), keyEquivalent: "")
        visItem.state = .on
        menu.addItem(visItem)
        self.visibilityItem = visItem
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Spawn random monster (dev)",
                                action: #selector(spawnDevMonster), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Despawn dev monsters",
                                action: #selector(despawnDevMonsters), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item

        watcher.onOutcome = { [weak self] outcome in self?.apply(outcome) }
        watcher.start()

        let idle = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.tickIdle() }
        idle.tolerance = 5
        RunLoop.main.add(idle, forMode: .common)
        idleTimer = idle

        let activity = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.tickActivity() }
        activity.tolerance = 1
        RunLoop.main.add(activity, forMode: .common)
        activityTimer = activity
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        idleTimer?.invalidate()
        activityTimer?.invalidate()
        projectWindows.forEach { persistFrame($1, forCWD: $0) }   // remember positions across launches
        projectWindows.values.forEach { $0.retire() }
        projectWindows.removeAll()
        despawnDevMonsters()
    }

    // MARK: - Project-driven windows (one per directory)

    private func apply(_ outcome: WatchOutcome) {
        for ref in outcome.started { spawn(ref, greet: didInitialApply) }
        for ref in outcome.changed { updateSessionCount(ref) }
        for cwd in outcome.ended { despawn(cwd) }
        didInitialApply = true   // sessions already live at launch don't greet; later ones do
    }

    private func spawn(_ ref: ProjectRef, greet: Bool) {
        guard projectWindows[ref.cwd] == nil else { return }
        let aimon = registry.aimon(forProjectCWD: ref.cwd, now: Date())   // mint or load persistent identity
        personalityByCwd[ref.cwd] = aimon.personality

        let window = CompanionWindow(seed: ref.seed, appearance: appearance)
        window.setSessionCount(ref.sessionCount, animated: false)
        if let f = aimon.lastFrame {
            window.setFrame(NSRect(x: f.x, y: f.y, width: f.width, height: f.height), display: false)
        } else {
            cascade(window, index: projectWindows.count)
        }
        window.onClick = { [weak self] in self?.focuser.focus(projectCWD: ref.cwd) }
        if aimonsVisible { window.orderFrontRegardless() }
        projectWindows[ref.cwd] = window
        sessionCountByCwd[ref.cwd] = ref.sessionCount
        nextIdleAt[ref.cwd] = Date().addingTimeInterval(TimeInterval(Int.random(in: 90...180)))  // first one sooner
        Log.lifecycle.notice("+ spawn \(aimon.name) [\(aimon.rarity.rawValue)] in \(projectLabel(ref.cwd)) sessions=\(ref.sessionCount) live=\(projectWindows.count)")
        if greet { speak(.sessionStarted, for: ref) }
    }

    /// Session count changed for a live project — the monster pops and remarks on it.
    private func updateSessionCount(_ ref: ProjectRef) {
        let prev = sessionCountByCwd[ref.cwd] ?? ref.sessionCount
        sessionCountByCwd[ref.cwd] = ref.sessionCount
        projectWindows[ref.cwd]?.setSessionCount(ref.sessionCount, animated: aimonsVisible)
        Log.lifecycle.notice("~ project \(projectLabel(ref.cwd)) sessions=\(ref.sessionCount)")
        speak(ref.sessionCount > prev ? .sessionJoined(count: ref.sessionCount) : .sessionLeft(count: ref.sessionCount),
              for: ref)
    }

    private func despawn(_ cwd: String) {
        if let window = projectWindows[cwd] { persistFrame(window, forCWD: cwd) }
        projectWindows[cwd]?.retire()
        projectWindows[cwd] = nil
        sessionCountByCwd[cwd] = nil
        lastSpokeByCwd[cwd] = nil
        personalityByCwd[cwd] = nil
        nextIdleAt[cwd] = nil
        Log.lifecycle.notice("- despawn project \(projectLabel(cwd)) live=\(projectWindows.count)")
    }

    private func persistFrame(_ window: CompanionWindow, forCWD cwd: String) {
        let f = window.frame
        registry.updateFrame(StoredFrame(x: Double(f.origin.x), y: Double(f.origin.y),
                                         width: Double(f.size.width), height: Double(f.size.height)),
                             forProjectCWD: cwd)
    }

    // MARK: - Speech

    /// Cadence-gated speech for a project: builds context, checks visibility + cooldown, then
    /// presents the template floor and (async) the Ollama upgrade.
    private func speak(_ trigger: SpeechTrigger, for ref: ProjectRef) {
        guard aimonsVisible, let window = projectWindows[ref.cwd] else { return }
        let now = Date()
        guard SpeechCadence.shouldSpeak(lastSpoke: lastSpokeByCwd[ref.cwd], now: now, cooldown: speechCooldown) else { return }
        lastSpokeByCwd[ref.cwd] = now
        let personality = personalityByCwd[ref.cwd] ?? PersonalityGenerator.personality(seed: ref.seed)
        let context = SpeechContext(personality: personality, trigger: trigger,
                                    projectName: projectName(ref.cwd), sessionCount: ref.sessionCount)
        speechEngine.speak(context) { [weak window] line in window?.showSpeech(line) }
        Log.lifecycle.notice("speak \(projectLabel(ref.cwd)) (\(context.archetype.rawValue))")
    }

    /// Occasional idle musings: when a project's monster has been quiet past its (randomized)
    /// idle interval, it shares a thought. Cadence-gated and visible-only.
    private func tickIdle() {
        guard aimonsVisible else { return }
        let now = Date()
        for cwd in projectWindows.keys {
            guard let due = nextIdleAt[cwd], now >= due else { continue }
            nextIdleAt[cwd] = now.addingTimeInterval(randomIdleInterval())
            let ref = ProjectRef(cwd: cwd, seed: ProjectIdentity.seed(forCWD: cwd),
                                 sessionCount: sessionCountByCwd[cwd] ?? 1)
            speak(.idleThought, for: ref)
        }
    }

    private func randomIdleInterval() -> TimeInterval { TimeInterval(Int.random(in: 240...480)) }  // 4–8 min

    /// "Reads the work": tail each live project's transcript off-main and react to the genuinely
    /// notable moments only — running tests and errors — when they newly occur. Editing/running/
    /// waiting are detected but intentionally not spoken (too frequent → annoying).
    private func tickActivity() {
        guard aimonsVisible, !activityProbing else { return }
        let cwds = Array(projectWindows.keys)
        guard !cwds.isEmpty else { return }
        activityProbing = true
        let reader = activityReader
        activityQueue.async { [weak self] in
            var results: [String: SessionActivity] = [:]
            for cwd in cwds { if let a = reader.activity(forCWD: cwd) { results[cwd] = a } }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activityProbing = false
                for (cwd, activity) in results {
                    guard self.lastActivityByCwd[cwd] != activity else { continue }   // only on change
                    self.lastActivityByCwd[cwd] = activity
                    guard activity == .error || activity == .testing else { continue } // speak only on notable
                    let ref = ProjectRef(cwd: cwd, seed: ProjectIdentity.seed(forCWD: cwd),
                                         sessionCount: self.sessionCountByCwd[cwd] ?? 1)
                    self.speak(.activity(activity), for: ref)
                }
            }
        }
    }

    private func projectLabel(_ cwd: String) -> String {
        #if DEBUG
        return cwd
        #else
        return (cwd as NSString).lastPathComponent
        #endif
    }

    /// The project's short name (last path component) — used in speech, never the full path.
    private func projectName(_ cwd: String) -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "this project" : name
    }

    // MARK: - Visibility toggle

    @objc private func toggleVisibility() {
        aimonsVisible.toggle()
        visibilityItem?.state = aimonsVisible ? .on : .off
        projectWindows.values.forEach { $0.setVisible(aimonsVisible) }   // hides bubble too
        devCompanions.forEach { aimonsVisible ? $0.orderFrontRegardless() : $0.orderOut(nil) }
        Log.lifecycle.notice("aimons \(aimonsVisible ? "visible" : "hidden")")   // watcher keeps running
    }

    // MARK: - Dev affordance

    @objc private func spawnDevMonster() {
        let seed = UInt64.random(in: 0..<UInt64.max)
        let window = CompanionWindow(seed: seed, appearance: appearance)
        cascade(window, index: devCompanions.count)
        if aimonsVisible { window.orderFrontRegardless() }
        devCompanions.append(window)
    }

    @objc private func despawnDevMonsters() {
        devCompanions.forEach { $0.retire() }
        devCompanions.removeAll()
    }

    private func cascade(_ window: CompanionWindow, index: Int) {
        let step = CGFloat(index % 6) * RenderConfig.default.cascadeStep
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
