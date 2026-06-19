import AppKit
import SwiftUI
import AIMonCore

/// A normal titled window hosting the SwiftUI Aidex gallery.
final class StableWindow: NSWindow {
    init(entries: [StableEntry]) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                   styleMask: [.titled, .closable, .resizable, .miniaturizable],
                   backing: .buffered, defer: false)
        title = "Aidex"
        isReleasedWhenClosed = false
        contentViewController = NSHostingController(rootView: StableView(entries: entries))
        center()
    }
}

extension PixelImage {
    func nsImage() -> NSImage? {
        guard let cg = makeCGImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }
}
