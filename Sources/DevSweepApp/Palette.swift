import AppKit
import DevSweepKit
import SwiftUI

/// Chart colors. Used for marks only: dots, rings, bars and cells. Everything
/// else uses system materials and semantic colors.
///
/// Dark values are the palette validated on the dark card surface (#27272B),
/// light values the one validated on a white card. In light mode three family
/// hues sit below 3:1 against white; that is acceptable only because every
/// segment also has a labeled legend row and a table row, so those labels
/// must stay in both appearances.
enum Palette {
    static func color(_ item: Item) -> Color {
        switch item {
        case .derivedData: Color(light: 0x104281, dark: 0x1C5CAB)
        case .deviceSupport: Color(light: 0x1C5CAB, dark: 0x3987E5)
        case .simulators: Color(light: 0x2A78D6, dark: 0x6DA7EC)
        case .xcodeBuilds: Color(light: 0x5598E7, dark: 0x9EC5F4)
        case .deviceInstalls: Color(light: 0x86B6EF, dark: 0xCDE2FB)
        case .swiftpmCache: Color(light: 0xC94A1C, dark: 0xD95926)
        case .swiftpmBuilds: Color(light: 0xEB6834, dark: 0xEE9A74)
        case .homebrew: Color(light: 0x1BAF7A, dark: 0x199E70)
        case .npmCache: Color(light: 0xEDA100, dark: 0xC98500)
        case .toolCaches: Color(light: 0xC9497C, dark: 0xD55181)
        case .gradleBuilds: Color(light: 0xE87BA4, dark: 0xEA9DBD)
        }
    }

    static func color(_ family: Family) -> Color {
        let hex = self.hex(family)
        return Color(light: hex.light, dark: hex.dark)
    }

    /// A family's color in each appearance, as sRGB hex.
    static func hex(_ family: Family) -> (light: UInt32, dark: UInt32) {
        switch family {
        case .xcode: (0x2A78D6, 0x3987E5)
        case .swiftPackages: (0xEB6834, 0xD95926)
        case .homebrew: (0x1BAF7A, 0x199E70)
        case .npm: (0xEDA100, 0xC98500)
        case .otherTools: (0xE87BA4, 0xD55181)
        }
    }

    /// Segments not measured yet: the ring is whole from the start and fills in.
    static let placeholder = Color.primary.opacity(0.07)
    /// Segments already cleaned.
    static let cleaned = Color.primary.opacity(0.12)
    /// The reclaimable part of the disk meter.
    static let reclaimable = Color(light: 0x2A78D6, dark: 0x3987E5)

    /// The window behind the panels, a step darker than them.
    static let backdrop = Color(light: 0xE2E2E5, dark: 0x161618)
    /// The selected segment of a glass segmented control.
    static let raisedSegment = Color(light: 0xFFFFFF, dark: 0x5E5E62)
    /// The rounded panels the sidebar, the center and the inspector sit in.
    static let panel = Color(light: 0xF9F9FA, dark: 0x262628)
    /// The fill of the window's main buttons: the accent color a step darker,
    /// so a white label reads at 4.5:1 or more on it. On the system blue as it
    /// is, the glass's own label came out light cyan, at 3.5:1 in the light
    /// appearance.
    static let action = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var accent = NSColor.controlAccentColor
        appearance.performAsCurrentDrawingAppearance {
            accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? accent
        }
        return Palette.darkened(accent, dark: isDark)
    })

    /// A bright color as text: mixed toward black, or white in the dark, so
    /// it reads on the panels.
    static func text(_ color: Color, dark: Bool) -> Color {
        color.mix(with: dark ? .white : .black, by: dark ? 0.35 : 0.45, in: .device)
    }

    /// The accent a step darker, for `action`.
    static func darkened(_ accent: NSColor, dark: Bool) -> NSColor {
        accent.blended(withFraction: dark ? 0.15 : 0.2, of: .black) ?? accent
    }
}

/// The window's main actions, like Clean: the system's prominent glass on
/// `Palette.action`, with a white label while it can be pressed in an active
/// window. Set on the button, a white foreground never reached the label,
/// which the glass drew light cyan. In an inactive window the glass turns
/// light gray and draws its own darker label, which white would wash out.
struct ProminentActionStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ProminentActionButton(configuration: configuration)
    }
}

private struct ProminentActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive
    let configuration: PrimitiveButtonStyleConfiguration

    var body: some View {
        Button(role: self.configuration.role) { self.configuration.trigger() } label: {
            if self.isEnabled, self.appearsActive {
                self.configuration.label.foregroundStyle(.white)
            } else {
                self.configuration.label
            }
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.action)
    }
}

extension PrimitiveButtonStyle where Self == ProminentActionStyle {
    static var prominentAction: ProminentActionStyle {
        ProminentActionStyle()
    }
}

/// Text a step quieter than the primary label that still reads at 4.5:1 or
/// more on every surface in the window, in both appearances; the system's
/// secondary label is 3.9:1 on the light panels. On a selected row it turns
/// light, as `.secondary` does.
struct MutedStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        if environment.backgroundProminence == .increased { return Color.white.opacity(0.85) }
        return Color(nsColor: NSColor(rgb: environment.colorScheme == .dark ? 0x9A9AA0 : 0x636368))
    }
}

extension ShapeStyle where Self == MutedStyle {
    static var muted: MutedStyle {
        MutedStyle()
    }
}

/// Animations that respect Reduce Motion: none when it is on.
@MainActor
enum Motion {
    static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func animation(_ animation: Animation = .default) -> Animation? {
        self.reduced ? nil : animation
    }
}

extension Color {
    /// A color that follows the appearance it is drawn in.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}
