import AppKit
import DevSweepKit
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

extension PaletteTests {
    /// The surfaces muted text sits on: the panel, and a card's fill over
    /// it, as the system draws that fill in the appearance.
    func surfaces(dark: Bool, increasedContrast: Bool) -> [NSColor] {
        let panel = NSColor(rgb: dark ? 0x262628 : 0xF9F9FA)
        let name: NSAppearance.Name = switch (dark, increasedContrast) {
        case (false, false): .aqua
        case (true, false): .darkAqua
        case (false, true): .accessibilityHighContrastAqua
        case (true, true): .accessibilityHighContrastDarkAqua
        }
        var fill = NSColor.quinarySystemFill
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            fill = NSColor.quinarySystemFill.usingColorSpace(.sRGB) ?? fill
        }
        let card = panel.blended(withFraction: fill.alphaComponent, of: fill.withAlphaComponent(1)) ?? panel
        return [panel, card]
    }

    func contrast(_ one: NSColor, _ other: NSColor) -> Double {
        let (a, b) = (self.luminance(one), self.luminance(other))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @Test
    func `with Increase Contrast a block's edge stands 3 to 1 from the card in its own hue, light and dark`() {
        for item in Item.allCases {
            for dark in [false, true] {
                let edge = Palette.edge(item, dark: dark)
                for surface in self.surfaces(dark: dark, increasedContrast: true) {
                    let ratio = self.contrast(edge, surface)
                    #expect(ratio >= 3, "\(item.rawValue), dark \(dark): \(ratio):1")
                }
            }
        }
    }
}
