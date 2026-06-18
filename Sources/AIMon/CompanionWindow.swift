import AppKit
import SpriteKit
import AIMonCore

/// A small, borderless, transparent, always-on-top window holding one monster.
final class CompanionWindow: NSPanel {
    private let skView: CompanionSKView
    private let minBound: CGSize
    private let maxBound: CGSize

    init(seed: UInt64, appearance: AppearanceProvider, pixelScale: CGFloat = 16) {
        let image = appearance.image(for: seed)
        let initial = CGSize(width: CGFloat(image.width) * pixelScale,
                             height: CGFloat(image.height) * pixelScale)
        self.minBound = CGSize(width: initial.width * 0.5, height: initial.height * 0.5)
        self.maxBound = CGSize(width: initial.width * 3.0, height: initial.height * 3.0)

        self.skView = CompanionSKView(frame: NSRect(origin: .zero, size: initial))
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

        skView.onScaleBy = { [weak self] factor in
            self?.scaleBy(factor)
        }

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

    private func scaleBy(_ factor: CGFloat) {
        var newW = frame.width * factor
        var newH = frame.height * factor
        newW = max(minBound.width, min(maxBound.width, newW))
        newH = max(minBound.height, min(maxBound.height, newH))
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let newFrame = NSRect(x: center.x - newW / 2, y: center.y - newH / 2,
                              width: newW, height: newH)
        setFrame(newFrame, display: true, animate: false)
        skView.scene?.size = CGSize(width: newW, height: newH)
    }
}
