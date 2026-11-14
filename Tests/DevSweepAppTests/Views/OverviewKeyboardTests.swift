import AppKit
import DevSweepKit
import SwiftUI
import Testing
@testable import DevSweepApp

/// The overview by keyboard, with the Mac's Keyboard navigation setting as
/// it comes, off: Tab stops at each row, largest first, and selects it, and
/// Space marks the row focused.
@MainActor
@Suite("Overview keyboard")
struct OverviewKeyboardTests {
    @Test
    func `Tab moves through the rows largest first, selecting each, and Space marks the one focused`() async {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        app.showResults(sampleResults)
        let ordered = app.scan.tally.ordered.map(\.item)
        let window = self.window(OverviewContent().environment(models: app))
        try? await Task.sleep(for: .milliseconds(200))

        // The first Tab enters the window's key view loop at the first row.
        // AppKit then turns each Tab into a move to the next key view,
        // which the test asks for directly: SwiftUI leaves a synthetic Tab
        // event to the window once it has focus.
        self.press("\t", keyCode: 48, in: window)
        var selected: [Item?] = []
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(100))
            selected.append(app.overview.selection)
            window.selectNextKeyView(nil)
        }
        #expect(selected == Array(ordered.prefix(3)))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(app.overview.selection == ordered[3])
        self.press(" ", keyCode: 49, in: window)
        #expect(app.marks.marked == [ordered[3]])
        self.press(" ", keyCode: 49, in: window)
        #expect(app.marks.marked.isEmpty)

        // Shift-Tab goes back.
        window.selectPreviousKeyView(nil)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(app.overview.selection == ordered[2])
    }

    private func window(_ view: some View) -> NSWindow {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 1100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        return window
    }

    private func press(_ key: String, keyCode: UInt16, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: key,
                charactersIgnoringModifiers: key,
                isARepeat: false,
                keyCode: keyCode)
            else {
                continue
            }
            window.sendEvent(event)
        }
    }
}
