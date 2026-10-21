import AppKit
import DevCleanKit
import SwiftUI

/// Chart colors. Used for marks only: dots, rings, bars and cells. Everything
/// else uses system materials and semantic colors.
///
/// Dark values are the palette validated for the dark card surface. Light
/// values move each ramp one step darker so the lightest marks stay visible
/// on a light card.
enum Palette {
    static func color(_ item: Item) -> Color {
        switch item {
        case .derivedData: Color(light: 0x0E3F7A, dark: 0x1C5CAB)
        case .deviceSupport: Color(light: 0x1C5CAB, dark: 0x3987E5)
        case .simulators: Color(light: 0x3987E5, dark: 0x6DA7EC)
        case .xcodeBuilds: Color(light: 0x6DA7EC, dark: 0x9EC5F4)
        case .deviceInstalls: Color(light: 0x9EC5F4, dark: 0xCDE2FB)
        case .swiftpmCache: Color(light: 0xB5461A, dark: 0xD95926)
        case .swiftpmBuilds: Color(light: 0xD95926, dark: 0xEE9A74)
        case .homebrew: Color(light: 0x127A56, dark: 0x199E70)
        case .npmCache: Color(light: 0x9E6800, dark: 0xC98500)
        case .toolCaches: Color(light: 0xB03A66, dark: 0xD55181)
        case .gradleBuilds: Color(light: 0xD55181, dark: 0xEA9DBD)
        }
    }

    static func color(_ family: Family) -> Color {
        switch family {
        case .xcode: Color(light: 0x1C5CAB, dark: 0x3987E5)
        case .swiftPackages: Color(light: 0xB5461A, dark: 0xD95926)
        case .homebrew: Color(light: 0x127A56, dark: 0x199E70)
        case .npm: Color(light: 0x9E6800, dark: 0xC98500)
        case .otherTools: Color(light: 0xB03A66, dark: 0xD55181)
        }
    }

    /// Segments not measured yet: the ring is whole from the start and fills in.
    static let placeholder = Color.primary.opacity(0.07)
    /// Segments already cleaned.
    static let cleaned = Color.primary.opacity(0.12)
    /// The reclaimable part of the disk meter.
    static let reclaimable = Color(light: 0x1C5CAB, dark: 0x3987E5)
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
            alpha: 1
        )
    }
}
