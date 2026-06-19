import SpriteKit

/// An SKView that fully owns mouse handling for its borderless panel: scroll-wheel resize, manual
/// window dragging, and click classification (single vs double vs drag).
///
/// We do the dragging ourselves (rather than `isMovableByWindowBackground`) because that AppKit
/// affordance swallows/!restarts mouse tracking on a non-activating panel, which made
/// `NSEvent.clickCount` unreliable — double-clicks never registered. Owning the events lets us
/// detect a double-click by timestamp, robustly, in tmux or a plain terminal alike.
final class CompanionSKView: SKView {
    /// Multiplicative scale factor (>1 grow, <1 shrink) + cursor location (global), for zoom.
    var onScaleBy: ((CGFloat, NSPoint) -> Void)?
    /// A single click that didn't move the window.
    var onClick: (() -> Void)?
    /// A double click that didn't move the window.
    var onDoubleClick: (() -> Void)?

    private var dragStartMouse: NSPoint?    // screen coords at mouse-down
    private var dragStartOrigin: NSPoint?   // window origin at mouse-down
    private var didDrag = false
    private var lastClickTime: TimeInterval = 0
    private var pendingSingleClick: DispatchWorkItem?
    private let dragThreshold: CGFloat = 3

    override func scrollWheel(with event: NSEvent) {
        let factor = 1.0 + (event.scrollingDeltaY * 0.005)
        let clamped = max(0.9, min(1.1, factor))
        onScaleBy?(clamped, NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startMouse = dragStartMouse, let startOrigin = dragStartOrigin else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - startMouse.x, dy = now.y - startMouse.y
        if abs(dx) > dragThreshold || abs(dy) > dragThreshold { didDrag = true }
        // setFrameOrigin is overridden to clamp on-screen, so dragging stays contained live.
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStartMouse = nil; dragStartOrigin = nil }
        if didDrag { didDrag = false; return }   // it was a drag, not a click

        let t = event.timestamp
        if t - lastClickTime < NSEvent.doubleClickInterval {
            lastClickTime = 0
            pendingSingleClick?.cancel(); pendingSingleClick = nil
            onDoubleClick?()
        } else {
            lastClickTime = t
            // Defer the single action; a second click within the interval upgrades it to a double.
            let work = DispatchWorkItem { [weak self] in self?.pendingSingleClick = nil; self?.onClick?() }
            pendingSingleClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        }
    }
}
