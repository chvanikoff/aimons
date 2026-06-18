import SpriteKit

/// An SKView that forwards scroll-wheel input as a resize request.
final class CompanionSKView: SKView {
    /// Called with a multiplicative scale factor (>1 grow, <1 shrink).
    var onScaleBy: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let factor = 1.0 + (event.scrollingDeltaY * 0.005)
        let clamped = max(0.9, min(1.1, factor))
        onScaleBy?(clamped)
    }
}
