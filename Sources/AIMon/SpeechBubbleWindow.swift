import AppKit
import AIMonCore

/// A small, transparent, non-activating text bubble shown above a companion, auto-dismissing
/// after a few seconds. A separate panel (not part of the sprite window) so crisp text and the
/// sprite's clamp/zoom math stay independent; it never steals focus or blocks clicks.
final class SpeechBubbleWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let container = NSView()
    private var dismissWork: DispatchWorkItem?

    private let maxWidth: CGFloat = 260
    private let padding: CGFloat = 10

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true       // a bubble must never block the user's clicks
        isReleasedWhenClosed = false

        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.88).cgColor
        container.layer?.cornerRadius = 10

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.maximumNumberOfLines = 5
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: padding * 0.8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding * 0.8),
        ])
        contentView = container
    }

    override var canBecomeKey: Bool { false }

    deinit { Log.lifecycle.debug("SpeechBubbleWindow released") }

    /// Show `text` centered above `anchorFrame` (the monster's window frame), sized to fit and
    /// clamped on-screen, auto-dismissing after `duration`.
    func show(_ text: String, above anchorFrame: NSRect, duration: TimeInterval) {
        label.stringValue = text
        label.preferredMaxLayoutWidth = maxWidth - 2 * padding
        let textSize = label.intrinsicContentSize
        let w = min(maxWidth, textSize.width + 2 * padding)
        let h = textSize.height + 1.6 * padding

        let proposed = NSRect(x: anchorFrame.midX - w / 2, y: anchorFrame.maxY + 6, width: w, height: h)
        let clamped = WindowGeometry.clamp(proposed, within: NSScreen.screens.map { $0.frame })
        setFrame(clamped, display: true)
        alphaValue = 1
        orderFrontRegardless()

        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.orderOut(nil) })
    }
}
