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
    private var aimonByCwd: [String: AIMon] = [:]                // cwd -> resident AIMon (cached from registry)
    private var behaviorByCwd: [String: BehaviorProfile] = [:]   // cwd -> personality-derived behaviour
    private var devCompanions: [CompanionWindow] = []
    private var aimonsVisible = true
    private let speechCooldown: TimeInterval = 4
    private let newSessionXP = 3     // experience gained when a genuinely new session begins
    private let activityXP = 1       // experience per notable change while working
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
        menu.addItem(NSMenuItem(title: "Open the Stable…", action: #selector(openStable), keyEquivalent: "s"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Spawn random monster (dev)",
                                action: #selector(spawnDevMonster), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Despawn dev monsters",
                                action: #selector(despawnDevMonsters), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Grant XP to active AIMons (dev)",
                                action: #selector(grantDevXP), keyEquivalent: ""))
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
        let now = Date()
        let base = registry.aimon(forProjectCWD: ref.cwd, now: now)   // mint or load persistent identity
        // Only a genuinely new session earns xp — relaunching the app shouldn't farm evolution.
        let evo = greet ? registry.addXP(newSessionXP, forProjectCWD: ref.cwd, now: now) : nil
        let aimon = evo?.aimon ?? base
        aimonByCwd[ref.cwd] = aimon
        let behavior = BehaviorProfileBuilder.profile(for: aimon.effectivePersonality)
        behaviorByCwd[ref.cwd] = behavior

        let (open, closed) = appearanceImages(for: aimon)
        let render = RenderConfig(bobAmplitude: CGFloat(behavior.bobAmplitude), bobDuration: behavior.bobDuration)
        let window = CompanionWindow(image: open, closedEyesImage: closed, name: aimon.name, renderConfig: render)
        window.setSessionCount(ref.sessionCount, animated: false)
        if let f = aimon.lastFrame {
            window.setFrame(NSRect(x: f.x, y: f.y, width: f.width, height: f.height), display: false)
        } else {
            cascade(window, index: projectWindows.count)
        }
        window.onDoubleClick = { [weak self] in self?.focuser.focus(projectCWD: ref.cwd) }
        if aimonsVisible { window.orderFrontRegardless() }
        projectWindows[ref.cwd] = window
        sessionCountByCwd[ref.cwd] = ref.sessionCount
        nextIdleAt[ref.cwd] = now.addingTimeInterval(TimeInterval(Int.random(in: 90...180)))  // first one sooner
        Log.lifecycle.notice("+ spawn \(aimon.name) [\(aimon.rarity.rawValue)] stage=\(aimon.stage) xp=\(aimon.xp) in \(projectLabel(ref.cwd)) sessions=\(ref.sessionCount) live=\(projectWindows.count)")
        if greet { speak(.sessionStarted, for: ref) }
        if evo?.didEvolve == true { announceEvolution(cwd: ref.cwd, toStage: evo!.toStage) }
    }

    /// Open + closed-eye images for a creature at its current rarity and evolution stage.
    private func appearanceImages(for aimon: AIMon) -> (PixelImage, PixelImage) {
        (appearance.image(for: aimon.seed, rarity: aimon.rarity, stage: aimon.stage),
         appearance.image(for: aimon.seed, rarity: aimon.rarity, stage: aimon.stage, eyesClosed: true))
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
        aimonByCwd[cwd] = nil
        behaviorByCwd[cwd] = nil
        nextIdleAt[cwd] = nil
        Log.lifecycle.notice("- despawn project \(projectLabel(cwd)) live=\(projectWindows.count)")
    }

    private func persistFrame(_ window: CompanionWindow, forCWD cwd: String) {
        let f = window.frame
        registry.updateFrame(StoredFrame(x: Double(f.origin.x), y: Double(f.origin.y),
                                         width: Double(f.size.width), height: Double(f.size.height)),
                             forProjectCWD: cwd)
    }

    // MARK: - Experience & evolution

    /// Grant experience to a live project's AIMon; on a stage-up, re-render its look and announce it.
    private func grantXP(_ amount: Int, to cwd: String) {
        guard let result = registry.addXP(amount, forProjectCWD: cwd, now: Date()) else { return }
        aimonByCwd[cwd] = result.aimon
        guard result.didEvolve else { return }
        behaviorByCwd[cwd] = BehaviorProfileBuilder.profile(for: result.aimon.effectivePersonality)  // matured cadence
        if let window = projectWindows[cwd] {
            let (open, closed) = appearanceImages(for: result.aimon)
            window.updateAppearance(image: open, closedEyesImage: closed)
        }
        Log.lifecycle.notice("✦ evolved \(result.aimon.name) \(result.fromStage)→\(result.toStage) in \(projectLabel(cwd))")
        announceEvolution(cwd: cwd, toStage: result.toStage)
    }

    /// A celebratory hop + bubble when a creature evolves (bypasses the speech cooldown — it's an
    /// event worth always marking). The fresh look is applied by the caller.
    private func announceEvolution(cwd: String, toStage: Int) {
        guard let window = projectWindows[cwd] else { return }
        window.celebrate()
        guard aimonsVisible else { return }
        window.showSpeech("✨ I evolved! Stage \(toStage)/\(Evolution.maxStage)")
        lastSpokeByCwd[cwd] = Date()
    }

    // MARK: - Speech

    /// Cadence-gated speech for a project: builds context, checks visibility + cooldown, then
    /// presents the template floor and (async) the Ollama upgrade.
    private func speak(_ trigger: SpeechTrigger, for ref: ProjectRef) {
        guard aimonsVisible, let window = projectWindows[ref.cwd] else { return }
        let now = Date()
        let cooldown = behaviorByCwd[ref.cwd]?.speechCooldown ?? speechCooldown
        guard SpeechCadence.shouldSpeak(lastSpoke: lastSpokeByCwd[ref.cwd], now: now, cooldown: cooldown) else { return }
        lastSpokeByCwd[ref.cwd] = now
        let personality = aimonByCwd[ref.cwd]?.effectivePersonality
            ?? PersonalityGenerator.personality(seed: ref.seed)
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
            let behavior = behaviorByCwd[cwd]
            nextIdleAt[cwd] = now.addingTimeInterval(randomIdleInterval(behavior))
            // Reserved/quiet creatures may simply keep to themselves this round.
            if let chance = behavior?.idleChance, Double.random(in: 0..<1) > chance { continue }
            let ref = ProjectRef(cwd: cwd, seed: ProjectIdentity.seed(forCWD: cwd),
                                 sessionCount: sessionCountByCwd[cwd] ?? 1)
            speak(.idleThought, for: ref)
            grantXP(1, to: cwd)   // just being around, keeping you company, counts
        }
    }

    /// Per-creature idle gap (talkative ones muse more often); falls back to the old 4–8 min.
    private func randomIdleInterval(_ behavior: BehaviorProfile?) -> TimeInterval {
        let lo = behavior?.idleMin ?? 240, hi = behavior?.idleMax ?? 480
        return TimeInterval(Int.random(in: lo...max(lo + 1, hi)))
    }

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
                    self.grantXP(self.activityXP, to: cwd)   // working alongside you matures it
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

    // MARK: - The Stable

    private var stableWindow: StableWindow?

    @objc private func openStable() {
        let active = Set(projectWindows.keys)
        let entries = registry.all().map { aimon in
            StableEntry(aimon: aimon,
                        image: appearance.image(for: aimon.seed, rarity: aimon.rarity, stage: aimon.stage).nsImage(),
                        isActive: active.contains(aimon.projectCWD))
        }
        let window = StableWindow(entries: entries)
        stableWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
        // Showcase the range: a random rarity and stage so dev spawns exercise the new looks.
        let rarity = Rarity.allCases.randomElement() ?? .common
        let stage = Int.random(in: 1...Evolution.maxStage)
        let open = appearance.image(for: seed, rarity: rarity, stage: stage)
        let closed = appearance.image(for: seed, rarity: rarity, stage: stage, eyesClosed: true)
        let window = CompanionWindow(image: open, closedEyesImage: closed, name: NameGenerator.name(seed: seed))
        cascade(window, index: devCompanions.count)
        if aimonsVisible { window.orderFrontRegardless() }
        devCompanions.append(window)
    }

    /// Dev: fast-forward evolution by granting a chunk of xp to every live AIMon.
    @objc private func grantDevXP() {
        for cwd in projectWindows.keys { grantXP(10, to: cwd) }
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
