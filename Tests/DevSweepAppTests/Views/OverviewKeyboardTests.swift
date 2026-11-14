import AppKit
import DevSweepKit
import SwiftUI
import Testing
@testable import DevSweepApp

/// The overview by keyboard, with Keyboard navigation off, as a Mac comes:
/// Tab stops only at what takes focus of its own, the rows and the
/// inspector's lines. With it on, every button is a stop too, so these
/// tests are skipped.
@MainActor
@Suite(
    "Overview keyboard",
    .enabled("Keyboard navigation is off, as a Mac comes") {
        await MainActor.run { !NSApplication.shared.isFullKeyboardAccessEnabled }
    })
struct OverviewKeyboardTests {
    @Test
    func `Tab moves through the rows largest first, selecting each, and Space marks the one focused`() async {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        app.showResults(sampleResults)
        app.overview.select(nil)
        let ordered = app.scan.tally.ordered.map(\.item)
        let window = self.window(OverviewContent().environment(models: app))
        defer { window.close() }

        for item in ordered[0...3] {
            await self.tab(in: window)
            await waitUntil { app.overview.selection == item }
            #expect(app.overview.selection == item)
        }
        self.space(in: window)
        await waitUntil { !app.marks.marked.isEmpty }
        #expect(app.marks.marked == [ordered[3]])
        self.space(in: window)
        await waitUntil { app.marks.marked.isEmpty }
        #expect(app.marks.marked.isEmpty)

        // Shift-Tab goes back, as AppKit's previous key view.
        window.selectPreviousKeyView(nil)
        await waitUntil { app.overview.selection == ordered[2] }
        #expect(app.overview.selection == ordered[2])
    }

    @Test
    func `in the inspector, Tab stops at each line and Space ticks it`() async {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        app.showResults(sampleResults)
        let window = self.window(ItemInspector().environment(models: app))
        defer { window.close() }

        await self.tab(in: window)
        self.space(in: window)
        await waitUntil { !app.marks.markedParts(of: .derivedData).isEmpty }
        // The largest project, then the shared compilation cache.
        #expect(app.marks.markedParts(of: .derivedData) == [.folder("/dd/P1")])

        await self.tab(in: window)
        self.space(in: window)
        await waitUntil { app.marks.markedParts(of: .derivedData).count == 2 }
        #expect(app.marks.markedParts(of: .derivedData) == [.folder("/dd/P1"), .compilationCache])
    }

    private func window(_ view: some View) -> NSWindow {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 1100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        // As a click in the window does.
        window.makeFirstResponder(host)
        return window
    }

    /// What Tab does: AppKit moves focus to the next key view. The tests ask
    /// for it directly, since a synthetic Tab event reaches SwiftUI only
    /// while it already has focus. Returns once focus has moved.
    private func tab(in window: NSWindow) async {
        let before = window.firstResponder
        window.selectNextKeyView(nil)
        await waitUntil { window.firstResponder !== before }
    }

    private func space(in window: NSWindow) {
        self.press(" ", keyCode: 49, in: window)
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
