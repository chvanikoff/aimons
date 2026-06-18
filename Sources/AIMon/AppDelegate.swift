import AppKit
import AIMonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var visibilityItem: NSMenuItem?
    private let appearance: AppearanceProvider = ProceduralAppearance()
    private let watcher = TranscriptWatcher()

    private let speechEngine = SpeechEngine()

    private var projectWindows: [String: CompanionWindow] = [:]   // cwd -> window (one monster per project)
    private var sessionCountByCwd: [String: Int] = [:]           // cwd -> last seen live session count
    private var lastSpokeByCwd: [String: Date] = [:]            // cwd -> last time the monster spoke (cadence)
    private var lastFrameByCwd: [String: NSRect] = [:]            // per-project position memory (outlives sessions)
    private var devCompanions: [CompanionWindow] = []
    private var aimonsVisible = true
    private let speechCooldown: TimeInterval = 4

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
        projectWindows.values.forEach { $0.retire() }
        projectWindows.removeAll()
        despawnDevMonsters()
    }

    // MARK: - Project-driven windows (one per directory)

    private func apply(_ outcome: WatchOutcome) {
        for ref in outcome.started { spawn(ref) }
        for ref in outcome.changed { updateSessionCount(ref) }
        for cwd in outcome.ended { despawn(cwd) }
    }

    private func spawn(_ ref: ProjectRef) {
        guard projectWindows[ref.cwd] == nil else { return }
        let window = CompanionWindow(seed: ref.seed, appearance: appearance)
        window.setSessionCount(ref.sessionCount, animated: false)
        if let frame = lastFrameByCwd[ref.cwd] {
            window.setFrame(frame, display: false)        // resume where this project's monster last sat
        } else {
            cascade(window, index: projectWindows.count)
        }
        if aimonsVisible { window.orderFrontRegardless() }
        projectWindows[ref.cwd] = window
        sessionCountByCwd[ref.cwd] = ref.sessionCount
        Log.lifecycle.notice("+ spawn project \(projectLabel(ref.cwd)) sessions=\(ref.sessionCount) live=\(projectWindows.count)")
    }

    /// Session count changed for a live project — the monster reacts (pop) and speaks.
    private func updateSessionCount(_ ref: ProjectRef) {
        let prev = sessionCountByCwd[ref.cwd] ?? ref.sessionCount
        sessionCountByCwd[ref.cwd] = ref.sessionCount
        let window = projectWindows[ref.cwd]
        window?.setSessionCount(ref.sessionCount, animated: aimonsVisible)
        guard aimonsVisible else {
            Log.lifecycle.notice("~ project \(projectLabel(ref.cwd)) sessions=\(ref.sessionCount)")
            return
        }
        let now = Date()
        guard SpeechCadence.shouldSpeak(lastSpoke: lastSpokeByCwd[ref.cwd], now: now, cooldown: speechCooldown) else {
            Log.lifecycle.notice("~ project \(projectLabel(ref.cwd)) sessions=\(ref.sessionCount) (cooldown)")
            return
        }
        lastSpokeByCwd[ref.cwd] = now
        let trigger: SpeechTrigger = ref.sessionCount > prev
            ? .sessionJoined(count: ref.sessionCount)
            : .sessionLeft(count: ref.sessionCount)
        let context = SpeechContext(archetype: PersonalityGenerator.archetype(seed: ref.seed),
                                    trigger: trigger,
                                    projectName: projectName(ref.cwd),
                                    sessionCount: ref.sessionCount)
        speechEngine.speak(context) { [weak window] line in window?.showSpeech(line) }
        Log.lifecycle.notice("~ project \(projectLabel(ref.cwd)) sessions=\(ref.sessionCount) speak(\(context.archetype.rawValue))")
    }

    private func despawn(_ cwd: String) {
        if let window = projectWindows[cwd] { lastFrameByCwd[cwd] = window.frame }
        projectWindows[cwd]?.retire()
        projectWindows[cwd] = nil
        sessionCountByCwd[cwd] = nil
        lastSpokeByCwd[cwd] = nil
        Log.lifecycle.notice("- despawn project \(projectLabel(cwd)) live=\(projectWindows.count)")
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
