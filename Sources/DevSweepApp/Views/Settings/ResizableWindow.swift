import AppKit
import SwiftUI

/// Lets the window it is in be resized from its edges. SwiftUI makes a
/// Settings window, unlike its other windows, without AppKit's resizable
/// style, whatever the scene's resizability; that resizability still sets
/// how small the window gets.
struct ResizableWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        Marker()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Adds the style as it lands in a window.
    final class Marker: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            self.window?.styleMask.insert(.resizable)
        }
    }
}
