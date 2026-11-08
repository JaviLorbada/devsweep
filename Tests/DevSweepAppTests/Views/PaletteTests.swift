import AppKit
import Testing
@testable import DevSweepApp

@Suite("Colors")
struct PaletteTests {
    /// The relative luminance of a color, as WCAG defines it.
    func luminance(_ color: NSColor) -> Double {
        let color = color.usingColorSpace(.sRGB) ?? color
        func linear(_ value: CGFloat) -> Double {
            value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }

    @Test
    func `a white label reads at 4.5 to 1 or more on the main buttons, on the system blue`() {
        // The system blue in each appearance, the accent most people keep.
        let light = Palette.darkened(NSColor(rgb: 0x007AFF), dark: false)
        let dark = Palette.darkened(NSColor(rgb: 0x0A84FF), dark: true)
        for fill in [light, dark] {
            #expect(1.05 / (self.luminance(fill) + 0.05) >= 4.5)
        }
        // The blue as it is wasn't enough: about 4.0 and 3.6.
        #expect(1.05 / (self.luminance(NSColor(rgb: 0x007AFF)) + 0.05) < 4.5)
    }
}
