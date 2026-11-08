#if DEBUG
import AppKit
import DevSweepKit
import SwiftUI

/// What a debug launch's probe reports: whether the window's content fits
/// it, and the menus.
@MainActor
extension DebugLaunch {
    /// Whether the window's content fits it: the split views' frames against
    /// the window, each column's width or collapsed state, and every scroll
    /// view whose content is wider than the view showing it.
    static func probe(_ app: AppCoordinator) -> String {
        guard let window = mainWindow, let content = window.contentView else { return "no window\n" }
        var lines: [String] = []
        let size = content.bounds.size
        lines
            .append(
                "window \(Int(window.frame.width))x\(Int(window.frame.height)) min "
                    + "\(Int(window.minSize.width))x\(Int(window.minSize.height))")
        lines.append("screen \(app.window.screen), inspector \(app.window.inspectorPlacement.rawValue)")
        if let timing = app.scan.scanTiming {
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
            if let controller = split.delegate as? NSSplitViewController {
                lines.append("split \(index) items: " + controller.splitViewItems.map { item in
                    String(
                        format: "%@ min %.0f max %.0f holding %.0f",
                        item.behavior == .sidebar ? "sidebar" : "other",
                        item.minimumThickness,
                        item.maximumThickness,
                        item.holdingPriority.rawValue)
                }.joined(separator: "; "))
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
        // The traffic lights, which the content runs under with no title bar strip.
        if let zoom = window.standardWindowButton(.zoomButton) {
            let frame = zoom.convert(zoom.bounds, to: nil)
            lines.append(String(
                format: "window buttons end at %.0f, centered %.1f from the top",
                frame.maxX,
                size.height - frame.midY))
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
        lines += self.menuLines()
        return lines.joined(separator: "\n") + "\n"
    }

    /// The menu bar as it stands: each menu, its items with their shortcuts,
    /// and which are disabled.
    static func menuLines() -> [String] {
        (NSApplication.shared.mainMenu?.items ?? []).compactMap { top in
            guard let menu = top.submenu else { return nil }
            let items = menu.items.filter { !$0.isHidden }.map { item -> String in
                if item.isSeparatorItem { return "|" }
                var text = item.title
                if !item.keyEquivalent.isEmpty {
                    let flags = item.keyEquivalentModifierMask
                    let modifiers = [
                        (NSEvent.ModifierFlags.control, "⌃"),
                        (.option, "⌥"),
                        (.shift, "⇧"),
                        (.command, "⌘"),
                    ]
                    .filter { flags.contains($0.0) }.map(\.1).joined()
                    text += " \(modifiers)\(item.keyEquivalent.uppercased())"
                }
                return item.isEnabled ? text : "\(text) (disabled)"
            }
            return "menu \(menu.title.isEmpty ? top.title : menu.title): \(items.joined(separator: ", "))"
        }
    }

    /// SwiftUI hosting views a few levels down: one per column and toolbar.
    static func collectHosts(_ view: NSView, depth: Int, into found: inout [NSView]) {
        guard depth < 14 else { return }
        let name = String(describing: type(of: view))
        if name.hasPrefix("NSHostingView") || name.hasPrefix("_NSCoreHostingView") { found.append(view) }
        for child in view.subviews {
            self.collectHosts(child, depth: depth + 1, into: &found)
        }
    }

    static func collect<T: NSView>(_ view: NSView, into found: inout [T]) {
        if let match = view as? T { found.append(match) }
        for child in view.subviews {
            self.collect(child, into: &found)
        }
    }
}
#endif
