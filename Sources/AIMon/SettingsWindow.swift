import AppKit
import SwiftUI

/// A normal titled window hosting the SwiftUI Settings view.
final class SettingsWindow: NSWindow {
    init(viewModel: SettingsViewModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
                   styleMask: [.titled, .closable, .miniaturizable],
                   backing: .buffered, defer: false)
        title = "AIMon Settings"
        isReleasedWhenClosed = false
        contentViewController = NSHostingController(rootView: SettingsView(vm: viewModel))
        center()
    }
}
