import AppKit
import DevCleanKit
import SwiftUI
import Testing
@testable import DevCleanApp

// The window's columns must be able to hold every screen at their minimum
// sizes. When content asks for more, AppKit's split view either grows past
// the window or collapses a column in the middle of a layout pass, which
// raised "more Update Constraints in Window passes than there are views".

@MainActor
@Suite("Window layout")
struct LayoutTests {
    @Test("The Xcode versions screen fits the narrowest center column")
    func xcodesScreenWidth() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .xcodeVersions
        let size = minimumSize(of: XcodesContent(), model: model)
        #expect(size.width <= WindowLayout.centerMinimumWidth, "needs \(size.width) points")
    }

    @Test("The Xcode inspector never asks the window for more height")
    func xcodeInspectorHeight() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .xcodeVersions
        let size = minimumSize(of: XcodeInspector(), model: model)
        #expect(size.height <= WindowLayout.minimumHeight, "needs \(size.height) points")
    }
}
