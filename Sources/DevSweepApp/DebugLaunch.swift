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
/// - `DEVSWEEP_SCREEN=xcodes|runtimes|android-studios|android-sdk|gradle|overview` switches screens once the scan
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
/// - `DEVSWEEP_THEN_WIDTHS=900,1400` then resizes to each width in turn.
/// - `DEVSWEEP_PROBE=/path/report.txt` then waits a few seconds, writes
///   whether the content fits the window (split views, columns, scroll views,
///   read from the view hierarchy, no screen recording needed), and quits.
/// - `DEVSWEEP_CAPTURE=/path/window.png` then draws the window, as the screen
///   shows it, into that file and quits. An app may capture its own windows
///   without screen recording permission.
/// - `DEVSWEEP_SETTINGS=Folders` instead opens Settings on that tab, captures
///   it there and quits.
/// - `DEVSWEEP_MENU=1` instead opens the menu bar item's panel, captures it
///   there and quits.
/// - `DEVSWEEP_APPEARANCE=light|dark` picks the appearance.
/// - `DEVSWEEP_ACTIVE=1` draws the window as active even when the app can't
///   be made active, as while the screen is locked: selected rows in the
///   selection color rather than gray.
enum DebugLaunch {
    static var isRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["DEVSWEEP_WINDOW_WIDTH", "DEVSWEEP_SCREEN", "DEVSWEEP_PROBE", "DEVSWEEP_CAPTURE"]
            .contains { environment[$0] != nil }
    }

    static var drawsActive: Bool {
        ProcessInfo.processInfo.environment["DEVSWEEP_ACTIVE"] == "1"
    }

    @MainActor
    static func run(_ model: AppModel) async {
        let environment = ProcessInfo.processInfo.environment
        guard self.isRequested else { return }
        await self.setUpWindow(environment)
        guard await self.waitForScan(model) else { return }
        await self.applyScreen(model, environment)
        await self.resizeInTurn(environment)
        if let tab = environment["DEVSWEEP_SETTINGS"], !tab.isEmpty {
            await self.captureSettings(tab: tab, to: environment["DEVSWEEP_CAPTURE"])
        }
        if !(environment["DEVSWEEP_MENU"] ?? "").isEmpty {
            await self.captureMenuBarPanel(to: environment["DEVSWEEP_CAPTURE"])
        }
        if let output = environment["DEVSWEEP_CAPTURE"], let window = mainWindow {
            // Drawn as the key window, so controls don't show their inactive look.
            NSApplication.shared.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(500))
            self.trace(
                "capturing; key window \(window.isKeyWindow), on screen \(window.occlusionState.contains(.visible)), "
                    + "scan button enabled \(model.engine != nil)")
            let appName = NSApplication.shared.mainMenu?.items.first?.submenu?.title ?? "-"
            self
                .trace(
                    "app menu \(appName), window title \(window.title), process \(ProcessInfo.processInfo.processName)")
            self.trace(self.capture(window, to: output) ? "captured \(output)" : "capture failed")
            if environment["DEVSWEEP_PROBE"] == nil { exit(0) }
        }
        self.trace("probing")
        guard let output = environment["DEVSWEEP_PROBE"] else { return }
        try? self.probe(model).write(toFile: output, atomically: true, encoding: .utf8)
        exit(0)
    }

    /// The appearance, then the width once the launch animation has settled.
    @MainActor
    private static func setUpWindow(_ environment: [String: String]) async {
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
    }

    /// Waits for the whole scan, tracing any change of width meanwhile.
    /// False when cancelled.
    @MainActor
    private static func waitForScan(_ model: AppModel) async -> Bool {
        self.trace("window \(Int(self.mainWindow?.frame.width ?? 0)) wide; waiting for the scan")
        var lastWidth = self.mainWindow?.frame.width ?? 0
        let start = Date()
        while model.isScanning || model.isLoadingExtras || model.isScanTaskRunning {
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
                    model.measuringItems.map(\.rawValue).joined(separator: ",")))
                lastWidth = width
            }
        }
        return true
    }

    /// The screen, the selection and a press, as clicks would make them.
    @MainActor
    private static func applyScreen(_ model: AppModel, _ environment: [String: String]) async {
        self.trace("scan done; switching to \(environment["DEVSWEEP_SCREEN"] ?? "-")")
        switch environment["DEVSWEEP_SCREEN"] {
        case "xcodes": model.screen = .xcodeVersions
        case "runtimes": model.screen = .simulatorRuntimes
        case "overview": model.screen = .overview
        case "blocks": model.chartStyle = .blocks
        case "android-studios": model.screen = .androidStudios
        case "android-sdk": model.screen = .androidSDK
        case "gradle": model.screen = .gradleCaches
        case "scanning": model.rewindScan(toMeasured: 5)
        default: break
        }
        if let id = environment["DEVSWEEP_SELECT"], !id.isEmpty { model.select(snapshotID: id) }
        switch environment["DEVSWEEP_CHART"] {
        case "blocks": model.chartStyle = .blocks
        case "ring": model.chartStyle = .ring
        default: break
        }
        if let label = environment["DEVSWEEP_PRESS"], !label.isEmpty, let window = mainWindow {
            try? await Task.sleep(for: .seconds(1))
            self.trace(self.press(label, in: window) ? "pressed \(label)" : "found nothing labeled \(label)")
        }
        if let points = environment["DEVSWEEP_SCROLL"].flatMap(Double.init), let window = mainWindow {
            try? await Task.sleep(for: .seconds(1))
            self.trace(self.scrollCenter(by: points, in: window))
        }
        try? await Task.sleep(for: .seconds(3))
    }

    /// Scrolls the center panel, the widest scroll view in the window, down
    /// from where it rests, as a scroll wheel would: no further than the end
    /// of its content.
    @MainActor
    private static func scrollCenter(by points: Double, in window: NSWindow) -> String {
        guard let content = window.contentView else { return "no content to scroll" }
        var scrolls: [NSScrollView] = []
        self.collect(content, into: &scrolls)
        guard let scroll = scrolls.filter({ !$0.isHidden }).max(by: { $0.frame.width < $1.frame.width }),
              let document = scroll.documentView
        else { return "no scroll view" }
        let clip = scroll.contentView
        let insets = clip.contentInsets
        var origin = clip.bounds.origin
        if document.isFlipped {
            let bottom = document.frame.maxY + insets.bottom - clip.bounds.height
            origin.y = max(origin.y, min(origin.y + points, bottom))
        } else {
            let top = document.frame.minY - insets.bottom
            origin.y = min(origin.y, max(origin.y - points, top))
        }
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
        return String(
            format: "scrolled the %.0f-wide scroll view to y %.0f of %.0f",
            scroll.frame.width,
            clip.bounds.origin.y,
            document.frame.height)
    }

    /// Any further widths, one after another, as a person dragging would.
    @MainActor
    private static func resizeInTurn(_ environment: [String: String]) async {
        for width in (environment["DEVSWEEP_THEN_WIDTHS"] ?? "").split(separator: ",").compactMap({ Double($0) }) {
            guard let window = mainWindow else { break }
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: true)
            await self.waitForSteadyWidth()
            try? await Task.sleep(for: .seconds(1))
            self.trace("then \(Int(window.frame.width)) wide")
        }
    }

    /// Opens Settings on a tab, captures it and quits.
    @MainActor
    private static func captureSettings(tab: String, to output: String?) async -> Never {
        let main = self.mainWindow
        // The app menu's Settings… item, as ⌘, would choose it.
        if let menu = NSApplication.shared.mainMenu?.items.first?.submenu,
           let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," })
        {
            menu.performActionForItem(at: index)
        }
        try? await Task.sleep(for: .seconds(1))
        // The Settings window is the one with a toolbar; the status item has a window too.
        if let settings = NSApplication.shared.windows
            .first(where: { $0.isVisible && $0 !== main && $0.toolbar != nil })
        {
            // Settings tabs are toolbar items.
            if let item = settings.toolbar?.items.first(where: { $0.label == tab }), let action = item.action {
                settings.toolbar?.selectedItemIdentifier = item.itemIdentifier
                NSApplication.shared.sendAction(action, to: item.target, from: item)
                self.trace("showed \(tab)")
            } else {
                self.trace("no tab \(tab)")
            }
            try? await Task.sleep(for: .seconds(1))
            if let output {
                self.trace(self.capture(settings, to: output) ? "captured \(output)" : "capture failed")
            }
        }
        exit(0)
    }

    /// Opens the menu bar item's panel, captures it and quits.
    @MainActor
    private static func captureMenuBarPanel(to output: String?) async -> Never {
        let before = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let button = NSApplication.shared.windows
            .filter { String(describing: type(of: $0)).contains("StatusBar") }
            .compactMap { self.findStatusButton(in: $0.contentView) }
            .first
        button?.performClick(nil)
        try? await Task.sleep(for: .seconds(1))
        let panel = NSApplication.shared.windows.first { $0.isVisible && !before.contains(ObjectIdentifier($0)) }
        self.trace(button == nil ? "no status item" : panel == nil ? "no panel" : "opened the menu bar panel")
        if let panel, let output {
            self.trace(self.capture(panel, to: output) ? "captured \(output)" : "capture failed")
        }
        exit(0)
    }

    @MainActor
    private static func findStatusButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        return view.subviews.lazy.compactMap { self.findStatusButton(in: $0) }.first
    }

    /// Presses the first element labeled `label`, searching the window's
    /// accessibility tree the way VoiceOver sees it.
    @MainActor
    private static func press(_ label: String, in window: NSWindow) -> Bool {
        var queue: [Any] = [window]
        var visited = 0
        while !queue.isEmpty, visited < 20000 {
            let element = queue.removeFirst()
            visited += 1
            guard let element = element as? NSAccessibilityElementProtocol & NSObjectProtocol else { continue }
            let object = element as AnyObject
            let title = object.accessibilityLabel?() ?? object.accessibilityTitle?()
            if title == label, object.accessibilityPerformPress?() == true { return true }
            if let children = object.accessibilityChildren?() { queue.append(contentsOf: children) }
        }
        return false
    }

    /// Draws the window as the window server composites it, glass included,
    /// which drawing the views into a bitmap leaves out. The function is
    /// obsolete in the SDK but still in CoreGraphics, so it is looked up.
    ///
    /// Once the screen has locked and the display slept, the window counts as
    /// hidden and is never drawn, and the image comes back empty. Then nothing
    /// is written: drawing the views instead leaves out most of SwiftUI's.
    @MainActor
    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage")
        else { return false }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        guard let windowNumber = UInt32(exactly: window.windowNumber) else { return false }
        // Including just this window; ignoring its shadow, at full resolution.
        guard let image = createImage(.null, 1 << 3, windowNumber, 1 << 0 | 1 << 3)?.takeRetainedValue()
        else { return false }
        let bitmap = NSBitmapImageRep(cgImage: image)
        if self.isEmpty(bitmap) {
            self.trace("the window server gave an empty image: the window isn't drawn while the screen is locked")
            return false
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// Whether every pixel on a coarse grid is fully transparent.
    private static func isEmpty(_ image: NSBitmapImageRep) -> Bool {
        let step = max(1, min(image.pixelsWide, image.pixelsHigh) / 24)
        for x in stride(from: 0, to: image.pixelsWide, by: step) {
            for y in stride(from: 0, to: image.pixelsHigh, by: step)
                where (image.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0
            {
                return false
            }
        }
        return true
    }

    /// Waits until the window's width has not changed for half a second.
    @MainActor
    private static func waitForSteadyWidth() async {
        var last = self.mainWindow?.frame.width ?? 0
        self.trace("width \(Int(last)) at launch")
        var steady = 0
        for _ in 0..<60 where steady < 5 {
            try? await Task.sleep(for: .milliseconds(100))
            let now = mainWindow?.frame.width ?? 0
            steady = now == last ? steady + 1 : 0
            last = now
        }
    }

    private static func trace(_ message: String) {
        FileHandle.standardError.write(Data("debug launch: \(message)\n".utf8))
    }

    @MainActor
    private static var mainWindow: NSWindow? {
        NSApplication.shared.windows.first { $0.isVisible && $0.contentView != nil }
    }

    /// Whether the window's content fits it: the split views' frames against
    /// the window, each column's width or collapsed state, and every scroll
    /// view whose content is wider than the view showing it.
    @MainActor
    private static func probe(_ model: AppModel) -> String {
        guard let window = mainWindow, let content = window.contentView else { return "no window\n" }
        var lines: [String] = []
        let size = content.bounds.size
        lines
            .append(
                "window \(Int(window.frame.width))x\(Int(window.frame.height)) min "
                    + "\(Int(window.minSize.width))x\(Int(window.minSize.height))")
        lines.append("screen \(model.screen), inspector \(model.debugInspectorShown ? "shown" : "hidden")")
        if let timing = model.scanTiming {
            lines.append(String(
                format: "scan: items measured after %.1fs, everything after %.1fs",
                timing.items,
                timing.total))
        }
        var problems = 0
        var splits: [NSSplitView] = []
        self.collect(content, into: &splits)
        for (index, split) in splits.enumerated() {
            let frame = split.convert(split.bounds, to: nil)
            let fits = frame.minX >= -0.5 && frame.maxX <= size.width + 0.5 && frame.minY >= -0.5 && frame.maxY <= size
                .height + 0.5
            if !fits { problems += 1 }
            let columns = split.arrangedSubviews
                .map {
                    split.isSubviewCollapsed($0) || $0.isHidden || $0.frame
                        .width < 1 ? "collapsed" : "\(Int($0.frame.width))"
                }
            lines.append(String(
                format: "split %d at %.0f,%.0f %.0fx%.0f %@ columns %@",
                index,
                frame.minX,
                frame.minY,
                frame.width,
                frame.height,
                fits ? "fits" : "OVERFLOWS",
                columns.joined(separator: " | ")))
        }
        var hosts: [NSView] = []
        self.collectHosts(content, depth: 0, into: &hosts)
        for host in hosts {
            let frame = host.convert(host.bounds, to: nil)
            let name = String(describing: type(of: host)).prefix(90)
            lines.append(String(
                format: "host at %.0f %.0fx%.0f fitting %.0fx%.0f %@",
                frame.minX,
                frame.width,
                frame.height,
                host.fittingSize.width,
                host.fittingSize.height,
                String(name)))
        }
        var scrolls: [NSScrollView] = []
        self.collect(content, into: &scrolls)
        for scroll in scrolls where !scroll.isHidden && scroll.frame.width > 1 {
            guard let document = scroll.documentView else { continue }
            let clipped = document.frame.width > scroll.contentView.bounds.width + 0.5
            if clipped { problems += 1 }
            let frame = scroll.convert(scroll.bounds, to: nil)
            lines.append(String(
                format: "scroll %@ at %.0f,%.0f %.0fx%.0f content %.0fx%.0f%@",
                String(describing: type(of: scroll)),
                frame.minX,
                frame.minY,
                frame.width,
                frame.height,
                document.frame.width,
                document.frame.height,
                clipped ? " CLIPPED" : ""))
        }
        lines.insert(problems == 0 ? "result: fits" : "result: \(problems) problem(s)", at: 2)
        return lines.joined(separator: "\n") + "\n"
    }

    /// SwiftUI hosting views a few levels down: one per column and toolbar.
    @MainActor
    private static func collectHosts(_ view: NSView, depth: Int, into found: inout [NSView]) {
        guard depth < 14 else { return }
        let name = String(describing: type(of: view))
        if name.hasPrefix("NSHostingView") || name.hasPrefix("_NSCoreHostingView") { found.append(view) }
        for child in view.subviews {
            self.collectHosts(child, depth: depth + 1, into: &found)
        }
    }

    @MainActor
    private static func collect<T: NSView>(_ view: NSView, into found: inout [T]) {
        if let match = view as? T { found.append(match) }
        for child in view.subviews {
            self.collect(child, into: &found)
        }
    }
}
#endif
