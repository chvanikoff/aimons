import AppKit
import AIMonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let appearance: AppearanceProvider = ProceduralAppearance()
    private let watcher = TranscriptWatcher()

    private var sessionWindows: [String: CompanionWindow] = [:]   // sessionId -> window
    private var seedBySession: [String: UInt64] = [:]             // sessionId -> project seed
    private var lastFrameBySeed: [UInt64: NSRect] = [:]           // per-project position memory (outlives sessions)
    private var devCompanions: [CompanionWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusItem.button(in: NSStatusBar.system)
        item.button?.title = "👾"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "AIMon (preview)", action: nil, keyEquivalent: ""))
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
        sessionWindows.values.forEach { $0.retire() }
        sessionWindows.removeAll()
        despawnDevMonsters()
    }

    // MARK: - Session-driven windows

    private func apply(_ outcome: WatchOutcome) {
        for ref in outcome.started { spawn(ref) }
        for id in outcome.ended { despawn(id) }
    }

    private func spawn(_ ref: SessionRef) {
        guard sessionWindows[ref.sessionId] == nil else { return }
        let window = CompanionWindow(seed: ref.seed, appearance: appearance)
        if let frame = lastFrameBySeed[ref.seed] {
            window.setFrame(frame, display: false)        // resume where this project's monster last sat
        } else {
            cascade(window, index: sessionWindows.count)
        }
        window.orderFrontRegardless()
        sessionWindows[ref.sessionId] = window
        seedBySession[ref.sessionId] = ref.seed
        #if DEBUG
        Log.lifecycle.notice("+ spawn \(ref.sessionId.prefix(8)) cwd=\(ref.cwd) live=\(sessionWindows.count)")
        #else
        Log.lifecycle.notice("+ spawn \(ref.sessionId.prefix(8)) live=\(sessionWindows.count)")
        #endif
    }

    private func despawn(_ sessionId: String) {
        if let window = sessionWindows[sessionId], let seed = seedBySession[sessionId] {
            lastFrameBySeed[seed] = window.frame
        }
        sessionWindows[sessionId]?.retire()
        sessionWindows[sessionId] = nil
        seedBySession[sessionId] = nil
        Log.lifecycle.notice("- despawn \(sessionId.prefix(8)) live=\(sessionWindows.count)")
    }

    // MARK: - Dev affordance

    @objc private func spawnDevMonster() {
        let seed = UInt64.random(in: 0..<UInt64.max)
        let window = CompanionWindow(seed: seed, appearance: appearance)
        cascade(window, index: devCompanions.count)
        window.orderFrontRegardless()
        devCompanions.append(window)
    }

    @objc private func despawnDevMonsters() {
        devCompanions.forEach { $0.close() }
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
