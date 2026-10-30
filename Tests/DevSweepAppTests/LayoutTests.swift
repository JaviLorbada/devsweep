import AppKit
import DevSweepKit
import SwiftUI
import Testing
@testable import DevSweepApp

// The window's columns must be able to hold every screen at their minimum
// sizes. When content asks for more, AppKit's split view either grows past
// the window or collapses a column in the middle of a layout pass, which
// raised "more Update Constraints in Window passes than there are views".

@MainActor
@Suite("Window layout")
struct LayoutTests {
    @Test
    func `the Xcode versions screen fits the narrowest center column`() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .xcodeVersions
        let size = minimumSize(of: XcodesContent(), model: model)
        #expect(size.width <= WindowLayout.centerMinimumWidth, "needs \(size.width) points")
    }

    @Test
    func `the Xcode inspector never asks the window for more height`() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .xcodeVersions
        let size = minimumSize(of: XcodeInspector(), model: model)
        #expect(size.height <= WindowLayout.minimumHeight, "needs \(size.height) points")
    }
}

extension LayoutTests {
    @Test
    func `the Simulator runtimes screen fits the narrowest center column`() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .simulatorRuntimes
        let size = minimumSize(of: RuntimesContent(), model: model)
        #expect(size.width <= WindowLayout.centerMinimumWidth, "needs \(size.width) points")
    }

    @Test
    func `the runtime inspector never asks the window for more height`() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .simulatorRuntimes
        model.selectedRuntime = sampleExtras.runtimes[1].id
        let size = minimumSize(of: RuntimeInspector(), model: model)
        #expect(size.height <= WindowLayout.minimumHeight, "needs \(size.height) points")
    }
}

extension LayoutTests {
    @Test
    func `the overview fits the narrowest center column`() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.showResults(sampleResults)
        for style in AppModel.ChartStyle.allCases {
            model.chartStyle = style
            let size = minimumSize(of: OverviewContent(), model: model)
            #expect(size.width <= WindowLayout.centerMinimumWidth, "\(style.rawValue) needs \(size.width) points")
        }
        let footer = minimumSize(of: OverviewFooter().padding(.horizontal, 22), model: model)
        #expect(footer.width <= WindowLayout.centerMinimumWidth, "the footer needs \(footer.width) points")
    }

    @Test
    func `the item inspector never asks the window for more height`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        model.showResults(sampleResults)
        model.selection = .derivedData
        let size = minimumSize(of: ItemInspector(), model: model)
        #expect(size.height <= WindowLayout.minimumHeight, "needs \(size.height) points")
    }

    @Test
    func `the inspector docks only while the center keeps its minimum, and nothing is ever clipped`() {
        let gap = WindowLayout.gap
        #expect(WindowLayout.detailWidthWithInspector >= gap + WindowLayout.centerMinimumWidth + gap + WindowLayout
            .inspectorWidth + gap)
        #expect(WindowLayout.inspectorHideBelow > WindowLayout.detailWidthWithInspector)
        #expect(WindowLayout.inspectorShowFrom > WindowLayout.inspectorHideBelow)
        #expect(WindowLayout.minimumWidth == WindowLayout.sidebar.min + WindowLayout.dividers + gap + WindowLayout
            .centerMinimumWidth + gap)
        #expect(WindowLayout.minimumWidth < 900, "900 points must still show the sidebar and the center")
        #expect(WindowLayout.sidebar.ideal + WindowLayout.inspectorShowFrom < 1100, "1100 points shows all three")
    }

    @Test
    func `the sidebar gives way to the center as the window narrows, within its own limits`() {
        // The sidebar's inset from the window's edge, then the center in its gaps.
        let rest = WindowLayout.gap + WindowLayout.gap + WindowLayout.centerMinimumWidth + WindowLayout.gap
        // The screenshot's window: 686 points, the sidebar dragged to 298.
        #expect(WindowLayout.sidebarMaximum(forWindowWidth: 686) + rest <= 686)
        #expect(WindowLayout.sidebarMaximum(forWindowWidth: WindowLayout.minimumWidth) >= WindowLayout.sidebar.min)
        #expect(WindowLayout.sidebarMaximum(forWindowWidth: 1280) == WindowLayout.sidebar.max)
        #expect(WindowLayout.sidebarMaximum(forWindowWidth: 300) == WindowLayout.sidebar.min)
    }

    @Test
    func `the header's row is centered on the window's controls' line, under its own height`() {
        // Measured in a debug window: the traffic lights are centered 26
        // points from the top, with the sidebar shown or hidden.
        #expect(WindowLayout.gap + CenterHeader.rowHeight / 2 == 26)
        // The row and the status under it fit the header.
        #expect(CenterHeader.rowHeight >= ChartStylePicker.height)
        #expect(CenterHeader.rowHeight + 16 <= CenterHeader.height)
    }

    @Test
    func `with the sidebar hidden the header's title starts after the window's controls`() {
        // The traffic lights and the sidebar's toggle end 144 points in.
        let titleStart = WindowLayout.gap + CenterHeader.horizontalPadding + CenterHeader.insetWithoutSidebar
        #expect(titleStart >= 144 + 8)
        // The controls drop their words by what the inset takes: the
        // screenshot's 686-point window, with the center 670 wide.
        let fit = CenterHeader.Fit(width: 670 - CenterHeader.insetWithoutSidebar)
        #expect(!fit.capsuleText && !fit.pickerText)
    }

    @Test
    func `the ring shrinks with its card, and the table drops its bar first`() {
        #expect(RingChart.diameter(forWidth: 800) == 240)
        #expect(RingChart.diameter(forWidth: 376) < 200)
        #expect(RingChart.diameter(forWidth: 100) == 150)
        #expect(!ItemsCard.showsBar(forWidth: WindowLayout.centerMinimumWidth))
        #expect(ItemsCard.showsBar(forWidth: 900))
    }
}

extension LayoutTests {
    @Test
    func `the worktrees screen fits the narrowest center column`() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .worktrees
        let size = minimumSize(of: WorktreesContent(), model: model)
        #expect(size.width <= WindowLayout.centerMinimumWidth, "needs \(size.width) points")
    }

    @Test
    func `the worktree inspector never asks the window for more height`() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .worktrees
        for worktree in sampleWorktrees {
            model.selectedWorktree = worktree.path
            let size = minimumSize(of: WorktreeInspector(), model: model)
            #expect(size.height <= WindowLayout.minimumHeight, "\(worktree.name) needs \(size.height) points")
        }
    }

    @Test
    func `the Android Studio screens fit the narrowest center column`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        model.android = sampleAndroid
        for (screen, size) in [
            (AppModel.Screen.androidStudios, minimumSize(of: AndroidStudiosContent(), model: model)),
            (.androidSDK, minimumSize(of: AndroidSDKContent(), model: model)),
            (.gradleCaches, minimumSize(of: GradleCachesContent(), model: model)),
        ] {
            #expect(size.width <= WindowLayout.centerMinimumWidth, "\(screen) needs \(size.width) points")
        }
    }

    @Test
    func `the Android inspector never asks the window for more height`() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        model.android = sampleAndroid
        for screen in [AppModel.Screen.androidStudios, .androidSDK, .gradleCaches] {
            model.screen = screen
            let size = minimumSize(of: AndroidInspector(), model: model)
            #expect(size.height <= WindowLayout.minimumHeight, "\(screen) needs \(size.height) points")
        }
    }
}
