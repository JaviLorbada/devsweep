import AppKit
import SwiftUI
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Resizable window")
struct ResizableWindowTests {
    @Test
    func `a window made without resizing, as SwiftUI makes Settings, resizes from its edges once it shows the view`() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 448),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        #expect(!window.styleMask.contains(.resizable))

        window.contentView = NSHostingView(rootView: Color.clear.background(ResizableWindow()))
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(window.styleMask.contains(.resizable))
    }
}
