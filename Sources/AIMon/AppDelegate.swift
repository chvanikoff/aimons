import AppKit
import AIMonCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var companion: CompanionWindow?
    private let appearance: AppearanceProvider = ProceduralAppearance()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusItem.button(in: NSStatusBar.system)
        item.button?.title = "👾"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "AIMon (preview)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "New random monster",
                                action: #selector(newMonster),
                                keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item

        showMonster(seed: 42)
    }

    @objc private func newMonster() {
        showMonster(seed: UInt64.random(in: 0..<UInt64.max))
    }

    private func showMonster(seed: UInt64) {
        companion?.close()
        let window = CompanionWindow(seed: seed, appearance: appearance)
        window.orderFrontRegardless()
        self.companion = window
    }
}

private extension NSStatusItem {
    static func button(in bar: NSStatusBar) -> NSStatusItem {
        bar.statusItem(withLength: NSStatusItem.variableLength)
    }
}
