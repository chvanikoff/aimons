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
