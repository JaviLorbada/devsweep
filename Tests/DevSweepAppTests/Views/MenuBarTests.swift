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
        let image = MenuBarGlyph.image
        #expect(image.isTemplate)
        #expect(image.size == CGSize(width: 16, height: 16))
        // Each gap and each segment measured along the ring, in points.
        let circumference = 2 * Double.pi * MenuBarGlyph.radius
        let segments = AppIconView.segments(gap: MenuBarGlyph.gap)
        #expect(segments.count == Family.allCases.count)
        #expect(MenuBarGlyph.gap * circumference >= 1.5)
        #expect(segments.allSatisfy { ($0.to - $0.from) * circumference >= 2 })
        #expect(MenuBarGlyph.radius + MenuBarGlyph.lineWidth / 2 <= MenuBarGlyph.side / 2)
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
}

extension NSBitmapImageRep {
    /// The relative luminance of the pixel at a point, as WCAG defines it.
    func luminance(atPoint point: CGPoint, scale: CGFloat) -> Double {
        guard let color = colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB)
        else { return 0 }
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
