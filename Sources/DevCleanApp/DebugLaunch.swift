#if DEBUG
import AppKit
import DevCleanKit
import SwiftUI

/// Development aid for checking the real window without a mouse. Debug builds only.
///
/// - `DEVCLEAN_SKIP=device-installs,...` leaves items out of the app's scan.
///   The first read of the CoreDevice container waits on a macOS prompt, so
///   unattended runs skip it.
/// - `DEVCLEAN_WINDOW_WIDTH=900` resizes the window once it is up.
/// - `DEVCLEAN_SCREEN=xcodes|runtimes|overview` switches screens once the scan
///   and the extras are done, the way a click in the sidebar does; `scanning`
///   instead winds the finished scan back to look half done.
/// - `DEVCLEAN_SELECT=swiftpm-builds` selects an item, or a runtime by its id.
/// - `DEVCLEAN_PRESS=label` then presses the control with that accessibility
///   label, as VoiceOver would.
/// - `DEVCLEAN_THEN_WIDTHS=900,1400` then resizes to each width in turn.
/// - `DEVCLEAN_PROBE=/path/report.txt` then waits a few seconds, writes
///   whether the content fits the window (split views, columns, scroll views,
///   read from the view hierarchy, no screen recording needed), and quits.
/// - `DEVCLEAN_CAPTURE=/path/window.png` then draws the window, as the screen
///   shows it, into that file and quits. An app may capture its own windows
///   without screen recording permission.
/// - `DEVCLEAN_APPEARANCE=light|dark` picks the appearance.
enum DebugLaunch {
    static var isRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["DEVCLEAN_WINDOW_WIDTH", "DEVCLEAN_SCREEN", "DEVCLEAN_PROBE", "DEVCLEAN_CAPTURE"].contains { environment[$0] != nil }
    }

    @MainActor
    static func run(_ model: AppModel) async {
        let environment = ProcessInfo.processInfo.environment
        guard isRequested else { return }
        switch environment["DEVCLEAN_APPEARANCE"] {
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        // SwiftUI animates the window to its restored size at launch; resize
        // only once that has settled, then check the new width holds.
        await waitForSteadyWidth()
        // Best launched with the frame as a defaults argument, `-"NSWindow
        // Frame main" "x y w h screen"`: SwiftUI keeps its own record of the
        // window's size and puts it back after a resize it didn't make.
        if let width = environment["DEVCLEAN_WINDOW_WIDTH"].flatMap(Double.init), let window = mainWindow,
           abs(window.frame.width - width) > 0.5 {
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: true)
            await waitForSteadyWidth()
        }
        trace("window \(Int(mainWindow?.frame.width ?? 0)) wide; waiting for the scan")
        var lastWidth = mainWindow?.frame.width ?? 0
        let start = Date()
        while model.isScanning || model.isLoadingExtras || model.isScanTaskRunning {
            if Task.isCancelled { trace("cancelled while waiting"); return }
            try? await Task.sleep(for: .milliseconds(100))
            let width = mainWindow?.frame.width ?? 0
            if width != lastWidth {
                trace(String(format: "at %.1fs width %.0f -> %.0f, measuring %@", Date().timeIntervalSince(start), lastWidth, width,
                             model.measuringItems.map(\.rawValue).joined(separator: ",")))
                lastWidth = width
            }
        }
        trace("scan done; switching to \(environment["DEVCLEAN_SCREEN"] ?? "-")")
        switch environment["DEVCLEAN_SCREEN"] {
        case "xcodes": model.screen = .xcodeVersions
        case "runtimes": model.screen = .simulatorRuntimes
        case "overview": model.screen = .overview
        case "scanning": model.rewindScan(toMeasured: 5)
        default: break
        }
        if let id = environment["DEVCLEAN_SELECT"], !id.isEmpty { model.select(snapshotID: id) }
        if let label = environment["DEVCLEAN_PRESS"], let window = mainWindow {
            try? await Task.sleep(for: .seconds(1))
            trace(press(label, in: window) ? "pressed \(label)" : "found nothing labeled \(label)")
        }
        try? await Task.sleep(for: .seconds(3))
        // Then any further widths, one after another, as a person dragging would.
        for width in (environment["DEVCLEAN_THEN_WIDTHS"] ?? "").split(separator: ",").compactMap({ Double($0) }) {
            guard let window = mainWindow else { break }
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: true)
            await waitForSteadyWidth()
            try? await Task.sleep(for: .seconds(1))
            trace("then \(Int(window.frame.width)) wide")
        }
        if let output = environment["DEVCLEAN_CAPTURE"], let window = mainWindow {
            // Drawn as the key window, so controls don't show their inactive look.
            NSApplication.shared.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(500))
            trace("capturing; key window \(window.isKeyWindow), scan button enabled \(model.engine != nil)")
            trace(capture(window, to: output) ? "captured \(output)" : "capture failed")
            if environment["DEVCLEAN_PROBE"] == nil { exit(0) }
        }
        trace("probing")
        guard let output = environment["DEVCLEAN_PROBE"] else { return }
        try? probe(model).write(toFile: output, atomically: true, encoding: .utf8)
        exit(0)
    }

    /// Presses the first element labeled `label`, searching the window's
    /// accessibility tree the way VoiceOver sees it.
    @MainActor
    private static func press(_ label: String, in window: NSWindow) -> Bool {
        var queue: [Any] = [window]
        var visited = 0
        while !queue.isEmpty, visited < 20_000 {
            let element = queue.removeFirst()
            visited += 1
            guard let element = element as? NSAccessibilityElementProtocol & NSObjectProtocol else { continue }
            let object = element as AnyObject
            let title = (object.accessibilityLabel?() ?? nil) ?? (object.accessibilityTitle?() ?? nil)
            if title == label, object.accessibilityPerformPress?() == true { return true }
            if let children = object.accessibilityChildren?() ?? nil { queue.append(contentsOf: children) }
        }
        return false
    }

    /// Draws the window as the window server composites it, glass included,
    /// which drawing the views into a bitmap leaves out. The function is
    /// obsolete in the SDK but still in CoreGraphics, so it is looked up.
    @MainActor
    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return false }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        // Including just this window; ignoring its shadow, at full resolution.
        guard let image = createImage(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | 1 << 3)?.takeRetainedValue(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// Waits until the window's width has not changed for half a second.
    @MainActor
    private static func waitForSteadyWidth() async {
        var last = mainWindow?.frame.width ?? 0
        trace("width \(Int(last)) at launch")
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
        lines.append("window \(Int(window.frame.width))x\(Int(window.frame.height)) min \(Int(window.minSize.width))x\(Int(window.minSize.height))")
        lines.append("screen \(model.screen), inspector \(model.debugInspectorShown ? "shown" : "hidden")")
        if let timing = model.scanTiming {
            lines.append(String(format: "scan: items measured after %.1fs, everything after %.1fs", timing.items, timing.total))
        }
        var problems = 0
        var splits: [NSSplitView] = []
        collect(content, into: &splits)
        for (index, split) in splits.enumerated() {
            let frame = split.convert(split.bounds, to: nil)
            let fits = frame.minX >= -0.5 && frame.maxX <= size.width + 0.5 && frame.minY >= -0.5 && frame.maxY <= size.height + 0.5
            if !fits { problems += 1 }
            let columns = split.arrangedSubviews.map { split.isSubviewCollapsed($0) || $0.isHidden || $0.frame.width < 1 ? "collapsed" : "\(Int($0.frame.width))" }
            lines.append(String(format: "split %d at %.0f,%.0f %.0fx%.0f %@ columns %@", index, frame.minX, frame.minY, frame.width, frame.height,
                                fits ? "fits" : "OVERFLOWS", columns.joined(separator: " | ")))
        }
        var hosts: [NSView] = []
        collectHosts(content, depth: 0, into: &hosts)
        for host in hosts {
            let frame = host.convert(host.bounds, to: nil)
            let name = String(describing: type(of: host)).prefix(90)
            lines.append(String(format: "host at %.0f %.0fx%.0f fitting %.0fx%.0f %@", frame.minX, frame.width, frame.height,
                                host.fittingSize.width, host.fittingSize.height, String(name)))
        }
        var scrolls: [NSScrollView] = []
        collect(content, into: &scrolls)
        for scroll in scrolls where !scroll.isHidden && scroll.frame.width > 1 {
            guard let document = scroll.documentView else { continue }
            let clipped = document.frame.width > scroll.contentView.bounds.width + 0.5
            if clipped { problems += 1 }
            let frame = scroll.convert(scroll.bounds, to: nil)
            lines.append(String(format: "scroll %@ at %.0f,%.0f %.0fx%.0f content %.0fx%.0f%@", String(describing: type(of: scroll)),
                                frame.minX, frame.minY, frame.width, frame.height, document.frame.width, document.frame.height,
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
        for child in view.subviews { collectHosts(child, depth: depth + 1, into: &found) }
    }

    @MainActor
    private static func collect<T: NSView>(_ view: NSView, into found: inout [T]) {
        if let match = view as? T { found.append(match) }
        for child in view.subviews { collect(child, into: &found) }
    }
}
#endif
