#if DEBUG
import AppKit
import DevSweepKit
import SwiftUI

/// Driving the window for a debug launch: scrolling, resizing, clicks,
/// key presses, menus, and capturing it or its parts into files.
extension DebugLaunch {
    /// Scrolls the center panel, the widest scroll view in the window, down
    /// from where it rests, as a scroll wheel would: no further than the end
    /// of its content.
    @MainActor
    static func scrollCenter(by points: Double, in window: NSWindow) -> String {
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
    static func resizeInTurn(_ environment: [String: String]) async {
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

    /// Opens Settings on a tab, scrolls it down `scroll` points when given,
    /// captures it and quits.
    @MainActor
    static func captureSettings(tab: String, scroll: Double?, to output: String?) async -> Never {
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
            if let scroll {
                self.trace(self.scrollCenter(by: scroll, in: settings))
                try? await Task.sleep(for: .milliseconds(500))
            }
            if let output {
                self.trace(self.capture(settings, to: output) ? "captured \(output)" : "capture failed")
            }
        }
        exit(0)
    }

    /// Opens the menu bar item's panel, captures it and quits; or, with
    /// `itemOnly`, captures the item in the menu bar.
    @MainActor
    static func captureMenuBarPanel(itemOnly: Bool, to output: String?) async -> Never {
        let before = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let statusWindow = NSApplication.shared.windows.first { window in
            String(describing: type(of: window)).contains("StatusBar")
                && self.findStatusButton(in: window.contentView) != nil
        }
        if itemOnly {
            // The window server hands back nothing for a status item's window,
            // so its button draws itself instead, on a clear background.
            if let button = self.findStatusButton(in: statusWindow?.contentView),
               let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds),
               let output
            {
                button.cacheDisplay(in: button.bounds, to: rep)
                let written = (try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: output))) != nil
                self.trace(written ? "captured \(output)" : "capture failed")
            } else {
                self.trace("no status item")
            }
            exit(0)
        }
        let button = self.findStatusButton(in: statusWindow?.contentView)
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
    static func findStatusButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        return view.subviews.lazy.compactMap { self.findStatusButton(in: $0) }.first
    }

    /// A window a chosen menu item opened, such as About.
    @MainActor static var opened: NSWindow?

    /// Chooses the menu item at `path`, its menu's title then its own, as
    /// the menu bar shows them.
    @MainActor
    static func perform(menuPath path: String) -> Bool {
        let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let menu = NSApplication.shared.mainMenu?.items
                  .first(where: { $0.title == parts[0] || $0.submenu?.title == parts[0] })?.submenu,
              let index = menu.items.firstIndex(where: { $0.title == parts[1] }),
              menu.items[index].isEnabled
        else { return false }
        menu.performActionForItem(at: index)
        return true
    }

    /// Clicks the window at `point`, in points from its top-left corner, with
    /// a mouse down and up sent to this app only. The up is queued first, so
    /// a drag the down starts, such as the title bar's, ends.
    @MainActor
    static func click(at point: CGPoint, in window: NSWindow) -> String {
        guard let content = window.contentView, let frameView = content.superview else { return "no window to click" }
        let location = NSPoint(x: point.x, y: window.frame.height - point.y)
        let hit = frameView.hitTest(frameView.convert(location, from: nil))
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0)
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return "could not make a click" }
        NSApplication.shared.postEvent(up, atStart: false)
        window.sendEvent(down)
        return String(
            format: "clicked %.0f,%.0f, key window %@: %@ %@, %@",
            point.x,
            point.y,
            window.isKeyWindow ? "yes" : "no",
            hit.map { String(describing: type(of: $0)) } ?? "nothing",
            hit?.isDescendant(of: content) == true ? "in the content" : "outside the content",
            hit?.mouseDownCanMoveWindow == true ? "drags the window" : "doesn't drag the window")
    }

    /// The sidebar column's width over the 0.6 seconds after it is told to
    /// hide, as "seconds:width" pairs, so its animation's length and curve
    /// can be read off. It is shown again afterwards.
    @MainActor
    static func sidebarTiming(in window: NSWindow) async -> String {
        guard let content = window.contentView else { return "no window" }
        var splits: [NSSplitView] = []
        self.collect(content, into: &splits)
        guard let split = splits.first, let column = split.arrangedSubviews.first else { return "no split view" }
        let toggle = #selector(NSSplitViewController.toggleSidebar(_:))
        let start = ProcessInfo.processInfo.systemUptime
        guard NSApplication.shared.sendAction(toggle, to: nil, from: nil) else { return "nothing toggles the sidebar" }
        var samples: [String] = []
        while ProcessInfo.processInfo.systemUptime - start < 0.6 {
            samples.append(String(
                format: "%.3f:%.0f",
                ProcessInfo.processInfo.systemUptime - start,
                split.isSubviewCollapsed(column) && column.isHidden ? 0 : column.frame.width))
            try? await Task.sleep(for: .milliseconds(8))
        }
        NSApplication.shared.sendAction(toggle, to: nil, from: nil)
        try? await Task.sleep(for: .seconds(1))
        return "sidebar width while hiding: " + samples.joined(separator: " ")
    }

    /// Presses the first element labeled `label`, searching the window's
    /// accessibility tree the way VoiceOver sees it.
    @MainActor
    static func press(_ label: String, in window: NSWindow) -> Bool {
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
    static func capture(_ window: NSWindow, to path: String) -> Bool {
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
    static func isEmpty(_ image: NSBitmapImageRep) -> Bool {
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
    static func waitForSteadyWidth() async {
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

    static func trace(_ message: String) {
        FileHandle.standardError.write(Data("debug launch: \(message)\n".utf8))
    }

    @MainActor
    static var mainWindow: NSWindow? {
        NSApplication.shared.windows.first { $0.isVisible && $0.contentView != nil }
    }
}
#endif
