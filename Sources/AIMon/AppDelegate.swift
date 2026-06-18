import AppKit
import AIMonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let appearance: AppearanceProvider = ProceduralAppearance()
    private let watcher = TranscriptWatcher()

    private var sessionWindows: [String: CompanionWindow] = [:]   // sessionId -> window
    private var seedBySession: [String: UInt64] = [:]             // sessionId -> project seed
    private var lastFrameBySeed: [UInt64: NSRect] = [:]           // remember where a project's monster sat
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
        if let frame = lastFrameBySeed[session.projectSeed] {
            window.setFrame(frame, display: false)   // resume where this project's monster last sat
        } else {
            cascade(window, index: sessionWindows.count)
        }
        window.orderFrontRegardless()
        sessionWindows[session.sessionId] = window
        seedBySession[session.sessionId] = session.projectSeed
        NSLog("AIMon: + spawn \(session.sessionId.prefix(8)) cwd=\(session.cwd) live=\(sessionWindows.count)")
    }

    private func handleSessionEnded(_ sessionId: String) {
        if let window = sessionWindows[sessionId], let seed = seedBySession[sessionId] {
            lastFrameBySeed[seed] = window.frame
        }
        sessionWindows[sessionId]?.close()
        sessionWindows[sessionId] = nil
        seedBySession[sessionId] = nil
        NSLog("AIMon: - despawn \(sessionId.prefix(8)) live=\(sessionWindows.count)")
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
