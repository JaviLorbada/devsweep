// Draws docs/social-preview.png, the 1280 by 640 image GitHub shows when
// the repository is linked: the icon, the name, what it does, and the ring
// cropped from the dark overview at 1280 points wide.
//
//   RELEASE_LOOK=1 SIDEBAR_WIDTH=240 WIDTH=1280 Scripts/snapshot.sh build/shots overview
//   swift Scripts/make_social_preview.swift docs/icon/icon_512x512@2x.png \
//     build/shots/overview-1280.png docs/social-preview.png
//
// GitHub has no API for it: upload it in Settings > General > Social preview.

import AppKit

let args = CommandLine.arguments
let icon = NSImage(contentsOfFile: args[1])!
let shot = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: args[2])))!
let out = args[3]

let w = 1280, h = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: the window's dark backdrop.
NSGradient(starting: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1),
           ending: NSColor(srgbRed: 0.14, green: 0.14, blue: 0.16, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -35)

// The ring and its legend, cropped from the window's screenshot.
let crop = NSRect(x: 550, y: 192, width: 1335, height: 560) // in the screenshot's pixels, from the top
let cg = shot.cgImage!.cropping(to: crop)!
let panelWidth: CGFloat = 616
let panelHeight = panelWidth * crop.height / crop.width
let panel = NSRect(x: CGFloat(w) - 64 - panelWidth, y: (CGFloat(h) - panelHeight) / 2, width: panelWidth, height: panelHeight)
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: panel, xRadius: 18, yRadius: 18).addClip()
NSImage(cgImage: cg, size: panel.size).draw(in: panel)
NSGraphicsContext.restoreGraphicsState()
NSColor(white: 1, alpha: 0.10).setStroke()
let border = NSBezierPath(roundedRect: panel.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
border.lineWidth = 1
border.stroke()

// The icon, the name and what it does.
icon.draw(in: NSRect(x: 64, y: 372, width: 168, height: 168))
func text(_ s: String, _ font: NSFont, _ color: NSColor, _ rect: NSRect) {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 4
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        .draw(with: rect, options: [.usesLineFragmentOrigin])
}
text("DevSweep", .systemFont(ofSize: 76, weight: .bold), .white, NSRect(x: 64, y: 252, width: 520, height: 100))
text("See how much space developer caches take up on your Mac, and clean what you choose.",
     .systemFont(ofSize: 29, weight: .regular), NSColor(white: 0.80, alpha: 1), NSRect(x: 66, y: 120, width: 500, height: 130))
text("A SwiftUI app and a command line tool for macOS 26",
     .systemFont(ofSize: 21, weight: .medium), NSColor(white: 0.55, alpha: 1), NSRect(x: 66, y: 66, width: 520, height: 34))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print(out)
