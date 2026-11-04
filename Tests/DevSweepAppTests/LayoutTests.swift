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
    func `the header's controls have room above them, and the inspector's first line shares their line`() {
        // Centered on the traffic lights' line, 26 points from the window's
        // top, the controls came within 2 to 4 points of the panel's edge.
        #expect(WindowLayout.controlInset >= 14)
        #expect(CenterHeader.rowHeight >= ChartStylePicker.height)
        #expect(WindowLayout.controlInset + CenterHeader.rowHeight / 2 == WindowLayout.topRowLine)
        // The eyebrow's line is about 13 points.
        #expect(WindowLayout.inspectorTopPadding + 13 / 2 == WindowLayout.topRowLine)
        // The inset, the row and the status under it fit the header.
        #expect(WindowLayout.controlInset + CenterHeader.rowHeight + 16 <= CenterHeader.height(sidebarHidden: false))
    }

    @Test
    func `with the sidebar hidden the title goes under the window's controls, and the controls after them`() {
        // The traffic lights and the sidebar's plain toggle end 124 points in.
        let controlsStart = WindowLayout.gap + CenterHeader.horizontalPadding + CenterHeader.insetWithoutSidebar
        #expect(controlsStart >= 124 + 12)
        // The title's line starts below the row, which is below the traffic
        // lights, centered 26 points down and 14 tall.
        #expect(WindowLayout.gap + WindowLayout.controlInset + CenterHeader.rowHeight >= 26 + 7)
        #expect(CenterHeader.height(sidebarHidden: true)
            == CenterHeader.height(sidebarHidden: false) + CenterHeader.titleLineHeight)
        // The controls drop their words by what the inset takes: in the
        // screenshot's 686-point window, with the center 670 wide, the
        // progress drops its text and Ring and Blocks keep theirs.
        let fit = CenterHeader.Fit(width: 670 - CenterHeader.insetWithoutSidebar)
        #expect(!fit.capsuleText && fit.pickerText)
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
