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

        skView.onScaleBy = { [weak self] factor, anchor in
            self?.scaleBy(factor, about: anchor)
        }

        let scene = CompanionScene(image: image, size: initial)
        skView.presentScene(scene)
        contentView = skView

        // Place it somewhere visible on first launch (clamped by setFrameOrigin).
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            setFrameOrigin(NSPoint(x: v.midX - initial.width / 2,
                                   y: v.midY - initial.height / 2))
        }
    }

    override var canBecomeKey: Bool { false }

    // MARK: - Keep the monster on screen

    /// Applied by AppKit during managed moves/resizes.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        WindowGeometry.clamp(frameRect, within: CompanionWindow.screenFrames())
    }

    /// Catches background-drag moves, which bypass constrainFrameRect on borderless windows.
    override func setFrameOrigin(_ point: NSPoint) {
        let proposed = CGRect(origin: point, size: frame.size)
        let clamped = WindowGeometry.clamp(proposed, within: CompanionWindow.screenFrames())
        super.setFrameOrigin(clamped.origin)
    }

    // MARK: - Resize

    private func scaleBy(_ factor: CGFloat, about anchor: NSPoint) {
        let zoomed = WindowGeometry.zoom(frame, factor: factor, about: anchor,
                                         minBound: minBound, maxBound: maxBound)
        let clamped = WindowGeometry.clamp(zoomed, within: CompanionWindow.screenFrames())
        setFrame(clamped, display: true)
        skView.scene?.size = clamped.size
    }

    private static func screenFrames() -> [CGRect] {
        NSScreen.screens.map { $0.frame }
    }
}
