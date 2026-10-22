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

extension LayoutTests {
    @Test("The Simulator runtimes screen fits the narrowest center column")
    func runtimesScreenWidth() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .simulatorRuntimes
        let size = minimumSize(of: RuntimesContent(), model: model)
        #expect(size.width <= WindowLayout.centerMinimumWidth, "needs \(size.width) points")
    }

    @Test("The runtime inspector never asks the window for more height")
    func runtimeInspectorHeight() {
        let home = TemporaryHome()
        let model = makeModel(home: home, extras: sampleExtras)
        model.screen = .simulatorRuntimes
        model.selectedRuntime = sampleExtras.runtimes[1].id
        let size = minimumSize(of: RuntimeInspector(), model: model)
        #expect(size.height <= WindowLayout.minimumHeight, "needs \(size.height) points")
    }
}

extension LayoutTests {
    @Test("The overview fits the narrowest center column")
    func overviewWidth() {
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

    @Test("The item inspector never asks the window for more height")
    func itemInspectorHeight() {
        let home = TemporaryHome()
        let model = makeModel(home: home)
        model.showResults(sampleResults)
        model.selection = .derivedData
        let size = minimumSize(of: ItemInspector(), model: model)
        #expect(size.height <= WindowLayout.minimumHeight, "needs \(size.height) points")
    }

    @Test("The inspector hides before the center would go below its minimum, and nothing is ever clipped")
    func collapseOrder() {
        let gap = WindowLayout.gap
        #expect(WindowLayout.detailWidthWithInspector >= gap + WindowLayout.centerMinimumWidth + gap + WindowLayout.inspectorWidth + gap)
        #expect(WindowLayout.inspectorHideBelow > WindowLayout.detailWidthWithInspector)
        #expect(WindowLayout.inspectorShowFrom > WindowLayout.inspectorHideBelow)
        #expect(WindowLayout.minimumWidth == WindowLayout.sidebar.min + WindowLayout.dividers + gap + WindowLayout.centerMinimumWidth + gap)
        #expect(WindowLayout.minimumWidth < 900, "900 points must still show the sidebar and the center")
        #expect(WindowLayout.sidebar.ideal + WindowLayout.inspectorShowFrom < 1100, "1100 points shows all three")
    }

    @Test("The ring shrinks with its card, and the table drops its bar first")
    func scaling() {
        #expect(RingChart.diameter(forWidth: 800) == 240)
        #expect(RingChart.diameter(forWidth: 376) < 200)
        #expect(RingChart.diameter(forWidth: 100) == 150)
        #expect(!ItemsCard.showsBar(forWidth: WindowLayout.centerMinimumWidth))
        #expect(ItemsCard.showsBar(forWidth: 900))
    }
}
