import AppKit
import AIMonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var companions: [CompanionWindow] = []
    private let appearance: AppearanceProvider = ProceduralAppearance()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusItem.button(in: NSStatusBar.system)
        item.button?.title = "👾"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "AIMon (preview)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Spawn random monster (dev)",
                                action: #selector(spawnMonster),
                                keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item

        spawnMonster()
    }

    /// Adds a new monster without disturbing existing ones (a dev/demo affordance and a
    /// preview of the eventual one-AIMon-per-session behaviour).
    @objc private func spawnMonster() {
        let seed: UInt64 = companions.isEmpty ? 42 : UInt64.random(in: 0..<UInt64.max)
        let window = CompanionWindow(seed: seed, appearance: appearance)

        // Cascade so stacked spawns don't perfectly overlap.
        let step = CGFloat(companions.count % 6) * 40
        var origin = window.frame.origin
        origin.x += step
        origin.y -= step
        window.setFrameOrigin(origin)

        window.orderFrontRegardless()
        companions.append(window)
    }
}

private extension NSStatusItem {
    static func button(in bar: NSStatusBar) -> NSStatusItem {
        bar.statusItem(withLength: NSStatusItem.variableLength)
    }
}
