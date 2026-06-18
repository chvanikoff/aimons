import SpriteKit

/// An SKView that forwards scroll-wheel input as a resize request anchored at the cursor.
final class CompanionSKView: SKView {
    /// Called with a multiplicative scale factor (>1 grow, <1 shrink) and the cursor
    /// location in global screen coordinates, so resizing can keep the cursor over the window.
    var onScaleBy: ((CGFloat, NSPoint) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let factor = 1.0 + (event.scrollingDeltaY * 0.005)
        let clamped = max(0.9, min(1.1, factor))
        onScaleBy?(clamped, NSEvent.mouseLocation)
    }
}
