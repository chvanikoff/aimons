import SpriteKit

/// An SKView that forwards scroll-wheel input as a resize request anchored at the cursor.
final class CompanionSKView: SKView {
    /// Called with a multiplicative scale factor (>1 grow, <1 shrink) and the cursor
    /// location in global screen coordinates, so resizing can keep the cursor over the window.
    var onScaleBy: ((CGFloat, NSPoint) -> Void)?
    /// Called on a click that did NOT move the window (a click, not a drag).
    var onClick: (() -> Void)?

    private var mouseDownWindowOrigin: NSPoint?

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
        // A click is a press+release where the window didn't move (a drag moves it via
        // isMovableByWindowBackground, changing the origin).
        if let start = mouseDownWindowOrigin, let now = window?.frame.origin,
           abs(start.x - now.x) < 3, abs(start.y - now.y) < 3 {
            onClick?()
        }
        mouseDownWindowOrigin = nil
        super.mouseUp(with: event)
    }
}
