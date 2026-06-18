import CoreGraphics

/// Pure geometry for positioning and resizing companion windows. No AppKit, fully testable.
public enum WindowGeometry {
    /// Smallest rectangle containing every input rect. nil if `rects` is empty.
    public static func unionRect(_ rects: [CGRect]) -> CGRect? {
        guard var u = rects.first else { return nil }
        for r in rects.dropFirst() { u = u.union(r) }
        return u
    }

    /// Clamp `frame` so it stays inside the bounding box of `screens`.
    /// Permits spanning the boundary between adjacent screens (interior to the union),
    /// but forbids passing the outer edge. If the window is larger than the union in a
    /// dimension, it is pinned to the min edge of that dimension.
    public static func clamp(_ frame: CGRect, within screens: [CGRect]) -> CGRect {
        guard let bounds = unionRect(screens) else { return frame }
        var x = frame.origin.x
        var y = frame.origin.y
        if frame.width >= bounds.width {
            x = bounds.minX
        } else {
            x = min(max(x, bounds.minX), bounds.maxX - frame.width)
        }
        if frame.height >= bounds.height {
            y = bounds.minY
        } else {
            y = min(max(y, bounds.minY), bounds.maxY - frame.height)
        }
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    /// Scale `frame` by `factor` about `anchor` (same coordinate space as `frame`), keeping
    /// the anchor's relative position fixed so a cursor at `anchor` stays over the window
    /// across repeated calls. Resulting size is clamped to [minBound, maxBound].
    public static func zoom(_ frame: CGRect,
                            factor: CGFloat,
                            about anchor: CGPoint,
                            minBound: CGSize,
                            maxBound: CGSize) -> CGRect {
        let relX = frame.width > 0 ? (anchor.x - frame.minX) / frame.width : 0.5
        let relY = frame.height > 0 ? (anchor.y - frame.minY) / frame.height : 0.5
        var w = frame.width * factor
        var h = frame.height * factor
        w = min(max(w, minBound.width), maxBound.width)
        h = min(max(h, minBound.height), maxBound.height)
        let originX = anchor.x - relX * w
        let originY = anchor.y - relY * h
        return CGRect(x: originX, y: originY, width: w, height: h)
    }
}
