#if DEBUG
import AppKit
import DevSweepKit
import SwiftUI

/// Development aid for checking the real window without a mouse. Debug builds only.
///
/// - `DEVSWEEP_SKIP=device-installs,...` leaves items out of the app's scan.
///   The first read of the CoreDevice container waits on a macOS prompt, so
///   unattended runs skip it.
/// - `DEVSWEEP_WINDOW_WIDTH=900` resizes the window once it is up.
/// - `DEVSWEEP_SIDEBAR_WIDTH=298` then sets the sidebar that wide, as
///   dragging its edge would; `DEVSWEEP_SIDEBAR=hidden` or `shown` hides or
///   shows it, as its toolbar button does, when it isn't already.
/// - `DEVSWEEP_SCREEN=xcodes|runtimes|android-studios|android-sdk|gradle|worktrees|overview` switches screens once the
/// scan
///   and the extras are done, the way a click in the sidebar does; `scanning`
///   instead winds the finished scan back to look half done, and `blocks`
///   shows the overview's blocks.
/// - `DEVSWEEP_SELECT=swiftpm-builds` selects an item, a runtime by its id,
///   or an Xcode by its folder's name, such as `Xcode-26.4.app`.
/// - `DEVSWEEP_CHART=blocks|ring` picks the overview's chart, as the toggle
///   in its header does. Pressing that toggle by its label finds nothing,
///   since the accessibility tree is empty while VoiceOver is off.
/// - `DEVSWEEP_SCROLL=200` scrolls the center panel down that many points.
/// - `DEVSWEEP_PRESS=label` then presses the control with that accessibility
///   label, as VoiceOver would.
/// - `DEVSWEEP_PERFORM=View/Blocks` then chooses that menu item, as a click or
///   its shortcut would (the app menu is `DevSweep/...`), and says which
///   windows are open after it and what it changed. A window it opens is
///   the one `DEVSWEEP_CAPTURE` captures.
/// - `DEVSWEEP_CLICK=1100,40;600,40` then clicks each point, in points from
///   the window's top-left corner, with events sent to this app alone (the
///   pointer doesn't move). It says which view the window found under each,
///   whether that is in the content or the title bar, whether a drag there
///   would move the window, and what changed.
/// - `DEVSWEEP_SIDEBAR_TIMING=1` then hides the sidebar, as its toolbar
///   button does, and traces the sidebar column's width every few
///   milliseconds while it animates, then shows it again.
/// - `DEVSWEEP_THEN_WIDTHS=900,1400` then resizes to each width in turn.
/// - `DEVSWEEP_PROBE=/path/report.txt` then waits a few seconds, writes
///   whether the content fits the window (split views, columns, scroll views,
///   read from the view hierarchy, no screen recording needed), and quits.
/// - `DEVSWEEP_CAPTURE=/path/window.png` then draws the window, as the screen
///   shows it, into that file and quits. An app may capture its own windows
///   without screen recording permission.
/// - `DEVSWEEP_SETTINGS=Folders` instead opens Settings on that tab, captures
///   it there and quits; with `DEVSWEEP_SCROLL`, scrolled down that far.
/// - `DEVSWEEP_MENU=1` instead opens the menu bar item's panel, captures it
///   there and quits; `DEVSWEEP_MENU=item` captures the item itself, as the
///   menu bar shows it.
/// - `DEVSWEEP_APPEARANCE=light|dark` picks the appearance.
/// - `DEVSWEEP_ACTIVE=1` draws the window as active even when the app can't
///   be made active, as while the screen is locked: selected rows in the
///   selection color rather than gray.
enum DebugLaunch {
    static var isRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["DEVSWEEP_WINDOW_WIDTH", "DEVSWEEP_SCREEN", "DEVSWEEP_PROBE", "DEVSWEEP_CAPTURE"]
            .contains { !(environment[$0] ?? "").isEmpty }
    }

    static var drawsActive: Bool {
        ProcessInfo.processInfo.environment["DEVSWEEP_ACTIVE"] == "1"
    }

    @MainActor
    static func run(_ app: AppCoordinator) async {
        let environment = ProcessInfo.processInfo.environment
        guard self.isRequested else { return }
        await self.setUpWindow(environment)
        guard await self.waitForScan(app) else { return }
        await self.applyScreen(app, environment)
        await self.resizeInTurn(environment)
        if let tab = environment["DEVSWEEP_SETTINGS"], !tab.isEmpty {
            await self.captureSettings(
                tab: tab,
                scroll: environment["DEVSWEEP_SCROLL"].flatMap(Double.init),
                to: environment["DEVSWEEP_CAPTURE"])
        }
        if !(environment["DEVSWEEP_MENU"] ?? "").isEmpty {
            await self.captureMenuBarPanel(
                itemOnly: environment["DEVSWEEP_MENU"] == "item",
                to: environment["DEVSWEEP_CAPTURE"])
        }
        if let output = environment["DEVSWEEP_CAPTURE"], let window = self.opened ?? mainWindow {
            // Drawn as the key window, so controls don't show their inactive look.
            NSApplication.shared.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(500))
            self.trace(
                "capturing; key window \(window.isKeyWindow), on screen \(window.occlusionState.contains(.visible)), "
                    + "scan button enabled \(app.scan.canScan)")
            let appName = NSApplication.shared.mainMenu?.items.first?.submenu?.title ?? "-"
            self
                .trace(
                    "app menu \(appName), window title \(window.title), process \(ProcessInfo.processInfo.processName)")
            self.trace(self.capture(window, to: output) ? "captured \(output)" : "capture failed")
            if (environment["DEVSWEEP_PROBE"] ?? "").isEmpty { exit(0) }
        }
        self.trace("probing")
        guard let output = environment["DEVSWEEP_PROBE"], !output.isEmpty else { return }
        try? self.probe(app).write(toFile: output, atomically: true, encoding: .utf8)
        exit(0)
    }

    /// The appearance, then the width once the launch animation has settled.
    @MainActor
    static func setUpWindow(_ environment: [String: String]) async {
        switch environment["DEVSWEEP_APPEARANCE"] {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        // SwiftUI animates the window to its restored size at launch; resize
        // only once that has settled, then check the new width holds.
        await self.waitForSteadyWidth()
        // Best launched with the frame as a defaults argument, `-"NSWindow
        // Frame main" "x y w h screen"`: SwiftUI keeps its own record of the
        // window's size and puts it back after a resize it didn't make.
        if let width = environment["DEVSWEEP_WINDOW_WIDTH"].flatMap(Double.init), let window = mainWindow,
           abs(window.frame.width - width) > 0.5
        {
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: true)
            await self.waitForSteadyWidth()
        }
        if let width = environment["DEVSWEEP_SIDEBAR_WIDTH"].flatMap(Double.init),
           let content = mainWindow?.contentView
        {
            var splits: [NSSplitView] = []
            self.collect(content, into: &splits)
            splits.first?.setPosition(width, ofDividerAt: 0)
            try? await Task.sleep(for: .milliseconds(500))
            self.trace("sidebar \(Int(splits.first?.arrangedSubviews.first?.frame.width ?? 0)) wide")
        }
        if let wanted = environment["DEVSWEEP_SIDEBAR"], ["hidden", "shown"].contains(wanted),
           let content = mainWindow?.contentView
        {
            var splits: [NSSplitView] = []
            self.collect(content, into: &splits)
            let hidden = splits.first.map { split in
                split.arrangedSubviews.first.map { split.isSubviewCollapsed($0) || $0.isHidden } ?? false
            } ?? false
            if hidden != (wanted == "hidden") {
                NSApplication.shared.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                try? await Task.sleep(for: .seconds(1))
            }
            self.trace("sidebar \(wanted), window \(Int(self.mainWindow?.frame.width ?? 0)) wide")
        }
    }

    /// Waits for the whole scan, tracing any change of width meanwhile.
    /// False when cancelled.
    @MainActor
    static func waitForScan(_ app: AppCoordinator) async -> Bool {
        self.trace("window \(Int(self.mainWindow?.frame.width ?? 0)) wide; waiting for the scan")
        var lastWidth = self.mainWindow?.frame.width ?? 0
        let start = Date()
        while app.scan.isScanning || app.scan.isLoadingExtras || app.scan.isScanTaskRunning {
            if Task.isCancelled {
                self.trace("cancelled while waiting")
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
            let width = self.mainWindow?.frame.width ?? 0
            if width != lastWidth {
                self.trace(String(
                    format: "at %.1fs width %.0f -> %.0f, measuring %@",
                    Date().timeIntervalSince(start),
                    lastWidth,
                    width,
                    app.scan.tally.measuringItems.map(\.rawValue).joined(separator: ",")))
                lastWidth = width
            }
        }
        return true
    }

    /// `DEVSWEEP_SCREEN`'s names for the screens.
    static let screens: [String: Screen] = [
        "overview": .overview,
        "xcodes": .xcodeVersions,
        "runtimes": .simulatorRuntimes,
        "android-studios": .androidStudios,
        "android-sdk": .androidSDK,
        "gradle": .gradleCaches,
        "worktrees": .worktrees,
    ]

    /// The screen, the selection and a press, as clicks would make them.
    @MainActor
    static func applyScreen(_ app: AppCoordinator, _ environment: [String: String]) async {
        self.trace("scan done; switching to \(environment["DEVSWEEP_SCREEN"] ?? "-")")
        switch environment["DEVSWEEP_SCREEN"] {
        case let name? where self.screens[name] != nil: app.window.screen = self.screens[name] ?? .overview
        case "blocks": app.window.chartStyle = .blocks
        case "scanning": app.rewindScan(toMeasured: 5)
        default: break
        }
        if let id = environment["DEVSWEEP_SELECT"], !id.isEmpty { app.select(snapshotID: id) }
        switch environment["DEVSWEEP_CHART"] {
        case "blocks": app.window.chartStyle = .blocks
        case "ring": app.window.chartStyle = .ring
        default: break
        }
        if let label = environment["DEVSWEEP_PRESS"], !label.isEmpty, let window = mainWindow {
            try? await Task.sleep(for: .seconds(1))
            self.trace(self.press(label, in: window) ? "pressed \(label)" : "found nothing labeled \(label)")
        }
        if let path = environment["DEVSWEEP_PERFORM"], !path.isEmpty {
            let before = Set(NSApplication.shared.windows.filter(\.isVisible).map(ObjectIdentifier.init))
            self.trace(self.perform(menuPath: path) ? "chose \(path)" : "no menu item \(path)")
            try? await Task.sleep(for: .seconds(1))
            let visible = NSApplication.shared.windows.filter(\.isVisible)
            self.opened = visible.first { !before.contains(ObjectIdentifier($0)) && $0.contentView != nil }
            self.trace("windows: \(visible.map { "\"\($0.title)\"" }.joined(separator: ", "))")
            self.trace(
                "screen \(app.window.screen), chart \(app.window.chartStyle.rawValue), "
                    + "inspector \(app.window.inspectorPlacement.rawValue), scanning \(app.scan.isScanning)")
        }
        if let clicks = environment["DEVSWEEP_CLICK"], !clicks.isEmpty, let window = mainWindow {
            for pair in clicks.split(separator: ";") {
                let numbers = pair.split(separator: ",").compactMap { Double($0) }
                guard numbers.count == 2 else { continue }
                try? await Task.sleep(for: .seconds(1))
                self.trace(self.click(at: CGPoint(x: numbers[0], y: numbers[1]), in: window))
                try? await Task.sleep(for: .seconds(1))
                self.trace(
                    "inspector \(app.window.inspectorPlacement.rawValue) (wanted \(app.window.wantsInspector), "
                        + "room \(app.window.inspectorHasRoom)), window \(Int(window.frame.width)) wide, "
                        + "scanning \(app.scan.isScanning), chart \(app.window.chartStyle.rawValue)")
            }
        }
        if environment["DEVSWEEP_SIDEBAR_TIMING"] == "1", let window = mainWindow {
            try? await Task.sleep(for: .seconds(1))
            await self.trace(self.sidebarTiming(in: window))
        }
        if let points = environment["DEVSWEEP_SCROLL"].flatMap(Double.init), let window = mainWindow {
            try? await Task.sleep(for: .seconds(1))
            self.trace(self.scrollCenter(by: points, in: window))
        }
        try? await Task.sleep(for: .seconds(3))
    }
}
#endif
