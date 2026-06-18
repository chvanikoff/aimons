import AppKit
import AIMonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var visibilityItem: NSMenuItem?
    private let appearance: AppearanceProvider = ProceduralAppearance()
    private let watcher = TranscriptWatcher()

    private var projectWindows: [String: CompanionWindow] = [:]   // cwd -> window (one monster per project)
    private var lastFrameByCwd: [String: NSRect] = [:]            // per-project position memory (outlives sessions)
    private var devCompanions: [CompanionWindow] = []
    private var aimonsVisible = true

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
        Log.lifecycle.notice("+ spawn project \(projectLabel(ref.cwd)) sessions=\(ref.sessionCount) live=\(projectWindows.count)")
    }

    /// Session count changed for a live project — the monster reacts (and M4 speech can use it).
    private func updateSessionCount(_ ref: ProjectRef) {
        projectWindows[ref.cwd]?.setSessionCount(ref.sessionCount, animated: aimonsVisible)
        Log.lifecycle.notice("~ project \(projectLabel(ref.cwd)) sessions=\(ref.sessionCount)")
    }

    private func despawn(_ cwd: String) {
        if let window = projectWindows[cwd] { lastFrameByCwd[cwd] = window.frame }
        projectWindows[cwd]?.retire()
        projectWindows[cwd] = nil
        Log.lifecycle.notice("- despawn project \(projectLabel(cwd)) live=\(projectWindows.count)")
    }

    private func projectLabel(_ cwd: String) -> String {
        #if DEBUG
        return cwd
        #else
        return (cwd as NSString).lastPathComponent
        #endif
    }

    // MARK: - Visibility toggle

    @objc private func toggleVisibility() {
        aimonsVisible.toggle()
        visibilityItem?.state = aimonsVisible ? .on : .off
        let windows = projectWindows.values + devCompanions
        if aimonsVisible {
            windows.forEach { $0.orderFrontRegardless() }
        } else {
            windows.forEach { $0.orderOut(nil) }   // hide only; the watcher keeps running
        }
        Log.lifecycle.notice("aimons \(aimonsVisible ? "visible" : "hidden")")
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
