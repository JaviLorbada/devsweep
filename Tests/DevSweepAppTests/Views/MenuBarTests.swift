import AppKit
import DevSweepKit
import Foundation
import SwiftUI
import Synchronization
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Menu bar")
struct MenuBarTests {
    @Test
    func `the menu bar item's text is the free space, never a view's description`() {
        for kilobytes: Int64 in [0, 900, 50_536_000, 4_000_000_000] {
            let space = DiskSpace(
                totalKilobytes: 5_000_000_000,
                availableKilobytes: kilobytes / 2,
                availableIncludingPurgeableKilobytes: kilobytes)
            let title = MenuBarLabel.title(space)
            #expect(title == SizeText.of(kilobytes: kilobytes))
            #expect(!title.contains("Image("))
            #expect(!title.contains("provider:"))
        }
    }

    @Test
    func `the menu bar glyph is a 16-point template ring whose five segments stay apart`() {
        let image = MenuBarGlyph(showsUpdateDot: false).image
        #expect(image.isTemplate)
        #expect(image.size == CGSize(width: 16, height: 16))
        // Each gap and each segment measured along the ring, in points.
        let circumference = 2 * Double.pi * MenuBarGlyph.radius
        let segments = IconRing.segments(gap: MenuBarGlyph.gap)
        #expect(segments.count == Family.allCases.count)
        #expect(MenuBarGlyph.gap * circumference >= 1.5)
        #expect(segments.allSatisfy { ($0.to - $0.from) * circumference >= 2 })
        #expect(MenuBarGlyph.radius + MenuBarGlyph.lineWidth / 2 <= MenuBarGlyph.side / 2)
    }

    @Test
    func `while an update waits, the glyph has an orange dot inside its ring, keeps its color, and says so`() {
        // The dot clears the ring's inside edge by a point or more.
        #expect(MenuBarGlyph.dotDiameter / 2 + 1 <= MenuBarGlyph.radius - MenuBarGlyph.lineWidth / 2)
        let image = MenuBarGlyph(showsUpdateDot: true).image
        #expect(!image.isTemplate, "the menu bar would draw the dot in its text color")
        // The menu bar reads VoiceOver the glyph's description, and the
        // label's own accessibility modifiers never reach it.
        #expect(image.accessibilityDescription == "\(ProductInfo.name), update available")
        for (name, ring) in [(NSAppearance.Name.vibrantLight, CGFloat(0)), (.vibrantDark, 1)] {
            let drawn = image.drawn(in: name)
            // The dot in the middle; the ring's strongest pixel below it, in
            // the label color's values, as the menu bar's text and the
            // template ring are.
            let dot = drawn.colorAt(x: 16, y: 16)?.usingColorSpace(.sRGB)
            #expect((dot?.redComponent ?? 0) > 0.8, "\(name.rawValue): \(String(describing: dot))")
            #expect((dot?.blueComponent ?? 1) < 0.4, "\(name.rawValue): \(String(describing: dot))")
            let ringPixels = (24..<32).flatMap { y in
                (0..<32).compactMap { x in
                    drawn.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                }
            }
            let strongest = ringPixels.max { $0.alphaComponent < $1.alphaComponent }
            #expect(abs((strongest?.redComponent ?? -1) - ring) < 0.02, "\(name.rawValue)")
            #expect(abs((strongest?.alphaComponent ?? 0) - 0.85) < 0.02, "\(name.rawValue)")
        }
    }

    @Test
    func `the panel's title row draws the volume name stronger than the free space, light and dark`() throws {
        let home = TemporaryHome()
        let app = makeApp(home: home)
        #expect(app.scan.diskSpace != nil)
        for scheme in [ColorScheme.light, .dark] {
            // On a material, as the menu bar shows it, where the hierarchical
            // styles turn vibrant: in light, `.secondary` drew darker than `.primary`.
            let renderer = ImageRenderer(content: MenuBarPanel()
                .background(.regularMaterial)
                .environment(models: app)
                .environment(\.colorScheme, scheme))
            renderer.scale = 2
            let image = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
            let background = image.luminance(atPoint: CGPoint(x: 4, y: 4), scale: 2)
            // The title row, just under the padding: the name from the left
            // edge, the free space up to the right one.
            let name = image.strongestContrast(
                in: CGRect(x: 16, y: 14, width: 110, height: 24),
                scale: 2,
                on: background)
            let free = image.strongestContrast(
                in: CGRect(x: 170, y: 14, width: 94, height: 24),
                scale: 2,
                on: background)
            #expect(free > 3, "no free space drawn in \(scheme)")
            #expect(name > free * 1.2, "the name \(name):1, the free space \(free):1 in \(scheme)")
        }
    }

    @Test
    func `the panel lists its actions a row each, Check for Updates… only in a build that updates itself`() {
        let home = TemporaryHome()
        // Without an updater the list has About, Settings… and Quit; with one,
        // Check for Updates… takes a row of its own.
        #expect(self.panelHeight(self.updatingApp(home: home, updater: FakeUpdater()))
            >= self.panelHeight(makeApp(home: home)) + 20)
    }

    @Test
    func `while an update waits, its row heads the panel's items in a group of its own`() {
        let updater = FakeUpdater()
        let app = self.updatingApp(home: TemporaryHome(), updater: updater)
        let height = self.panelHeight(app)
        updater.setWaitingUpdate(.available)
        // A row, and a separator under it.
        #expect(self.panelHeight(app) >= height + 30)
    }

    @Test
    func `while an update waits, its row leads with the menu bar item's orange dot, light and dark`() throws {
        let updater = FakeUpdater()
        let app = self.updatingApp(home: TemporaryHome(), updater: updater)
        for scheme in [ColorScheme.light, .dark] {
            #expect(try self.updateDotPixels(app, scheme: scheme) == 0, "\(scheme)")
        }
        for update in [WaitingUpdate.available, .ready] {
            updater.setWaitingUpdate(update)
            for scheme in [ColorScheme.light, .dark] {
                // An 8-point dot at twice the size: some 200 pixels.
                #expect(try self.updateDotPixels(app, scheme: scheme) > 100, "\(update) in \(scheme)")
            }
        }
    }

    private func updatingApp(home: TemporaryHome, updater: FakeUpdater) -> AppCoordinator {
        AppCoordinator(
            environment: testEnvironment(home: home),
            store: InMemoryScanStore(),
            preferences: Preferences(storage: InMemoryPreferencesStore()),
            notifier: SilentNotificationPoster(),
            updater: updater,
            dependencies: Dependencies(tools: .unavailable))
    }

    private func panelHeight(_ app: AppCoordinator) -> CGFloat {
        NSHostingController(rootView: MenuBarPanel().environment(models: app))
            .sizeThatFits(in: CGSize(width: 280, height: 2000)).height
    }

    /// How many of the panel's pixels, drawn at twice its size, are the
    /// update dot's color. No family's color is that close to it.
    private func updateDotPixels(_ app: AppCoordinator, scheme: ColorScheme) throws -> Int {
        let renderer = ImageRenderer(content: MenuBarPanel()
            .environment(models: app)
            .environment(\.colorScheme, scheme))
        renderer.scale = 2
        let image = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
        var dotColor: NSColor?
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            dotColor = Palette.updateDotColor.usingColorSpace(.sRGB)
        }
        let dot = try #require(dotColor)
        var count = 0
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                // The renderer's pixels are sRGB, and `colorAt` labels them
                // calibrated RGB: converting them would shift them, so their
                // components are compared as they are.
                guard let color = image.colorAt(x: x, y: y) else {
                    continue
                }
                if abs(color.redComponent - dot.redComponent) < 0.02,
                   abs(color.greenComponent - dot.greenComponent) < 0.02,
                   abs(color.blueComponent - dot.blueComponent) < 0.02
                {
                    count += 1
                }
            }
        }
        return count
    }
}

extension NSImage {
    /// The image drawn at twice its size, in an appearance, as the menu bar
    /// would draw it.
    func drawn(in appearance: NSAppearance.Name) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(self.size.width * 2),
            pixelsHigh: Int(self.size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)!
        rep.size = self.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            self.draw(in: NSRect(origin: .zero, size: self.size))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}

extension NSBitmapImageRep {
    /// The relative luminance of the pixel at a point, as WCAG defines it.
    func luminance(atPoint point: CGPoint, scale: CGFloat) -> Double {
        guard let color = colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB)
        else {
            return 0
        }
        func linear(_ value: CGFloat) -> Double {
            value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }

    /// The highest contrast ratio any pixel in `rect`, in points, has with
    /// `background`: what text there is drawn in, where it is solid.
    func strongestContrast(in rect: CGRect, scale: CGFloat, on background: Double) -> Double {
        var strongest = 1.0
        for y in stride(from: rect.minY, to: rect.maxY, by: 1 / scale) {
            for x in stride(from: rect.minX, to: rect.maxX, by: 1 / scale) {
                let luminance = self.luminance(atPoint: CGPoint(x: x, y: y), scale: scale)
                let ratio = (max(luminance, background) + 0.05) / (min(luminance, background) + 0.05)
                strongest = max(strongest, ratio)
            }
        }
        return strongest
    }
}
