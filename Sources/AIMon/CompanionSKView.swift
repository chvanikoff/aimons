import SpriteKit

/// An SKView that forwards scroll-wheel input as a resize request anchored at the cursor, and
/// distinguishes a single click (show last message) from a double click (focus the session) from a
/// drag (move the window).
final class CompanionSKView: SKView {
    /// Called with a multiplicative scale factor (>1 grow, <1 shrink) and the cursor
    /// location in global screen coordinates, so resizing can keep the cursor over the window.
    var onScaleBy: ((CGFloat, NSPoint) -> Void)?
    /// A single click that did NOT move the window.
    var onClick: (() -> Void)?
    /// A double click that did NOT move the window.
    var onDoubleClick: (() -> Void)?

    private var mouseDownWindowOrigin: NSPoint?
    private var pendingSingleClick: DispatchWorkItem?

    override func scrollWheel(with event: NSEvent) {
        let factor = 1.0 + (event.scrollingDeltaY * 0.005)
        let clamped = max(0.9, min(1.1, factor))
        onScaleBy?(clamped, NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownWindowOrigin = window?.frame.origin
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownWindowOrigin = nil; super.mouseUp(with: event) }
        // A click is a press+release where the window didn't move (a drag moves it via
        // isMovableByWindowBackground, changing the origin).
        guard let start = mouseDownWindowOrigin, let now = window?.frame.origin,
              abs(start.x - now.x) < 3, abs(start.y - now.y) < 3 else {
            pendingSingleClick?.cancel(); pendingSingleClick = nil
            return
        }
        if event.clickCount >= 2 {
            // The first click of a double already scheduled a single — cancel it, fire double.
            pendingSingleClick?.cancel(); pendingSingleClick = nil
            onDoubleClick?()
        } else {
            // Defer the single action briefly; if a second click lands, the double cancels it.
            let work = DispatchWorkItem { [weak self] in self?.pendingSingleClick = nil; self?.onClick?() }
            pendingSingleClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        }
    }
}
