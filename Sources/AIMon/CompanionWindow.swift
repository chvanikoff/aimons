import AppKit
import SpriteKit
import AIMonCore

/// A small, borderless, transparent, always-on-top window holding one monster.
final class CompanionWindow: NSPanel {
    private let skView: CompanionSKView
    private let minBound: CGSize
    private let maxBound: CGSize
    private let displayName: String
    private var lastSpeech: String?
    /// Called on a double-click that didn't move the window (e.g. focus the session).
    var onDoubleClick: (() -> Void)?

    init(image: PixelImage, closedEyesImage: PixelImage, name: String = "AImon",
         renderConfig: RenderConfig = .default) {
        self.displayName = name
        let initial = CGSize(width: CGFloat(image.width) * renderConfig.pixelScale,
                             height: CGFloat(image.height) * renderConfig.pixelScale)
        self.minBound = CGSize(width: initial.width * renderConfig.minScale,
                               height: initial.height * renderConfig.minScale)
        self.maxBound = CGSize(width: initial.width * renderConfig.maxScale,
                               height: initial.height * renderConfig.maxScale)

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
        // Dragging is handled manually in CompanionSKView (AppKit's background-drag swallowed mouse
        // tracking on this non-activating panel, making double-clicks unrecognisable).
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        // Keep NSPanel's default isReleasedWhenClosed = false: we own the window via the
        // AppDelegate dictionary, and close()+isReleasedWhenClosed=true use-after-frees under ARC
        // (observed SIGSEGV). We dispose via retire() (orderOut + drop the reference) instead.
        isReleasedWhenClosed = false

        skView.onScaleBy = { [weak self] factor, anchor in
            self?.scaleBy(factor, about: anchor)
        }
        skView.onClick = { [weak self] in self?.showLastOrGreeting() }   // single click → talk
        skView.onDoubleClick = { [weak self] in
            (self?.skView.scene as? CompanionScene)?.reactExcited()       // pet jump
            self?.onDoubleClick?()                                        // → focus the session
        }

        let scene = CompanionScene(image: image, closedEyesImage: closedEyesImage, size: initial,
                                   renderConfig: renderConfig)
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

    deinit { Log.lifecycle.debug("CompanionWindow released") }

    /// Swap to a freshly rendered look (after evolving), keeping size and position.
    func updateAppearance(image: PixelImage, closedEyesImage: PixelImage) {
        (skView.scene as? CompanionScene)?.setTextures(image: image, closedEyesImage: closedEyesImage)
    }

    /// Tear down for removal: stop SpriteKit's render loop, drop the scene and view hierarchy
    /// (releasing the texture and the display link that would otherwise outlive the window),
    /// and `orderOut`. We deliberately do NOT `close()` — `close()` with a strong ARC reference
    /// held use-after-frees (observed SIGSEGV). After this, dropping the dictionary reference
    /// lets ARC reclaim the window.
    func retire() {
        if let bubble { removeChildWindow(bubble) }
        bubble?.dismiss()
        bubble?.orderOut(nil)
        skView.isPaused = true
        skView.presentScene(nil)
        skView.removeFromSuperview()
        contentView = nil
        orderOut(nil)
    }

    // MARK: - Speech bubble

    private var bubble: SpeechBubbleWindow?

    /// Render a speech bubble above the monster. The bubble is attached as a child window so it
    /// follows the monster when dragged. (Cadence/anti-spam is governed by the caller.)
    func showSpeech(_ text: String) {
        lastSpeech = text
        if bubble == nil { bubble = SpeechBubbleWindow() }
        guard let bubble else { return }
        removeChildWindow(bubble)                  // re-anchor cleanly above the current position
        bubble.show(text, above: frame, duration: CompanionWindow.readingDuration(for: text))
        addChildWindow(bubble, ordered: .above)    // AppKit now keeps it pinned as the monster moves
        (skView.scene as? CompanionScene)?.reactTalk()
    }

    /// Single click: re-show the last thing it said (instant — no LLM wait), or greet if it hasn't
    /// spoken yet.
    private func showLastOrGreeting() {
        showSpeech(lastSpeech ?? "Hi! I'm \(displayName).")
    }

    /// Generous, length-aware on-screen time so a bubble is comfortably readable (≈2–3× the old
    /// flat 6s for typical lines).
    static func readingDuration(for text: String) -> TimeInterval {
        let words = text.split { $0 == " " || $0 == "\n" }.count
        return min(24, max(10, Double(words) * 1.0 + 5))
    }

    /// Show/hide both the monster and its bubble (for the menubar visibility toggle).
    func setVisible(_ visible: Bool) {
        if visible {
            orderFrontRegardless()
        } else {
            bubble?.orderOut(nil)
            orderOut(nil)
        }
    }

    // MARK: - Session count (context the monster reacts to)

    private var sessionCount = 1

    /// Update how many live sessions this project has. On an increase (a new session joined),
    /// the monster gives a brief reaction. `animated` is false for the initial spawn and while
    /// hidden.
    func setSessionCount(_ count: Int, animated: Bool) {
        let increased = count > sessionCount
        sessionCount = count
        if animated && increased { (skView.scene as? CompanionScene)?.reactExcited() }
    }

    /// A celebratory hop (e.g. on evolving).
    func celebrate() { (skView.scene as? CompanionScene)?.reactExcited() }

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
        bubble?.reposition(above: clamped)   // keep the bubble centered over the resized monster
    }

    private static func screenFrames() -> [CGRect] {
        NSScreen.screens.map { $0.frame }
    }
}
