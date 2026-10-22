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
///   and the extras are done, the way a click in the sidebar does.
/// - `DEVCLEAN_PROBE=/path/report.txt` then waits a few seconds, writes
///   whether the content fits the window (split views, columns, scroll views,
///   read from the view hierarchy, no screen recording needed), and quits.
enum DebugLaunch {
    static var isRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["DEVCLEAN_WINDOW_WIDTH", "DEVCLEAN_SCREEN", "DEVCLEAN_PROBE"].contains { environment[$0] != nil }
    }

    @MainActor
    static func run(_ model: AppModel) async {
        let environment = ProcessInfo.processInfo.environment
        guard isRequested else { return }
        try? await Task.sleep(for: .milliseconds(500))
        if let width = environment["DEVCLEAN_WINDOW_WIDTH"].flatMap(Double.init), let window = mainWindow {
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: true)
        }
        while model.isScanning || model.isLoadingExtras {
            try? await Task.sleep(for: .milliseconds(200))
        }
        switch environment["DEVCLEAN_SCREEN"] {
        case "xcodes": model.screen = .xcodeVersions
        case "runtimes": model.screen = .simulatorRuntimes
        case "overview": model.screen = .overview
        default: break
        }
        try? await Task.sleep(for: .seconds(3))
        guard let output = environment["DEVCLEAN_PROBE"] else { return }
        try? probe(model).write(toFile: output, atomically: true, encoding: .utf8)
        exit(0)
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
        lines.append("screen \(model.screen)")
        if let timing = model.scanTiming {
            lines.append(String(format: "scan items %.1fs, extras %.1fs", timing.items, timing.extras))
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

    @MainActor
    private static func collect<T: NSView>(_ view: NSView, into found: inout [T]) {
        if let match = view as? T { found.append(match) }
        for child in view.subviews { collect(child, into: &found) }
    }
}
#endif
