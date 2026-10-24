import AppKit
import DevSweepKit
import SwiftUI

/// The app's icon, drawn: a ring in the five family colors, as the overview
/// draws them in dark mode, on a dark rounded square. A placeholder with
/// intent until there is real artwork. `Scripts/make_icon.sh` renders it into
/// `docs/icon`, PNGs and the `.icns` the bundle gets; artwork can replace
/// those files without touching this.
struct AppIconView: View {
    /// Each family's share of the ring, clockwise from the top.
    static let shares: [(family: Family, share: Double)] = [
        (.xcode, 0.40), (.swiftPackages, 0.20), (.homebrew, 0.16), (.npm, 0.13), (.otherTools, 0.11),
    ]
    /// The gap between two segments, as a share of the ring.
    static let gap = 0.014

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // macOS's icon grid: an 824-point tile with a 185-point corner on
            // a 1024-point canvas, the rest left for the shadow the system adds.
            let tile = side * 824 / 1024
            ZStack {
                RoundedRectangle(cornerRadius: side * 185 / 1024, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(nsColor: NSColor(rgb: 0x2C2C30)), Color(nsColor: NSColor(rgb: 0x151517))],
                        startPoint: .top,
                        endPoint: .bottom))
                    .frame(width: tile, height: tile)
                self.ring(lineWidth: tile * 0.15)
                    .frame(width: tile * 0.62 - tile * 0.15, height: tile * 0.62 - tile * 0.15)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func ring(lineWidth: CGFloat) -> some View {
        ZStack {
            ForEach(Array(Self.segments.enumerated()), id: \.offset) { _, segment in
                Circle()
                    .trim(from: segment.from, to: segment.to)
                    .stroke(
                        Color(nsColor: NSColor(rgb: Palette.hex(segment.family).dark)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    /// Where each segment starts and ends around the ring, gaps taken out.
    static var segments: [(family: Family, from: Double, to: Double)] {
        var start = 0.0
        return self.shares.map { family, share in
            defer { start += share }
            return (family, start + self.gap / 2, start + share - self.gap / 2)
        }
    }
}

#if DEBUG
/// With `DEVSWEEP_ICON=/path/AppIcon.iconset`, draws `AppIconView` at every
/// size an iconset holds into that folder, for `Scripts/make_icon.sh`.
enum AppIconRenderer {
    /// The files an iconset needs and their sides in pixels.
    static let sizes: [(name: String, pixels: Int)] = [16, 32, 128, 256, 512].flatMap { side in
        [("icon_\(side)x\(side).png", side), ("icon_\(side)x\(side)@2x.png", side * 2)]
    }

    @MainActor
    static func runIfAsked() {
        guard let folder = ProcessInfo.processInfo.environment["DEVSWEEP_ICON"] else { return }
        for (name, pixels) in self.sizes {
            // Drawn at each size rather than scaled down, so small sizes stay crisp.
            let renderer = ImageRenderer(content: AppIconView().frame(width: CGFloat(pixels), height: CGFloat(pixels)))
            renderer.scale = 1
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else {
                FileHandle.standardError.write(Data("could not draw \(name)\n".utf8))
                exit(1)
            }
            try? png.write(to: URL(fileURLWithPath: folder).appending(path: name))
        }
        exit(0)
    }
}
#endif
