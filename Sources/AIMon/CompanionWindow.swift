import AppKit
import SpriteKit
import AIMonCore

/// A small, borderless, transparent, always-on-top window holding one monster.
final class CompanionWindow: NSPanel {
    private let skView: SKView

    init(seed: UInt64, appearance: AppearanceProvider, pixelScale: CGFloat = 16) {
        let image = appearance.image(for: seed)
        let initial = CGSize(width: CGFloat(image.width) * pixelScale,
                             height: CGFloat(image.height) * pixelScale)

        self.skView = SKView(frame: NSRect(origin: .zero, size: initial))
        skView.allowsTransparency = true

        super.init(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isMovableByWindowBackground = true   // drag the monster to move it
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false

        let scene = CompanionScene(image: image, size: initial)
        skView.presentScene(scene)
        contentView = skView

        // Place it somewhere visible on first launch.
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            setFrameOrigin(NSPoint(x: v.midX - initial.width / 2,
                                   y: v.midY - initial.height / 2))
        }
    }

    override var canBecomeKey: Bool { false }
}
