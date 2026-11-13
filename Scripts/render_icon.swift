// Draws an app bundle's icon into a PNG, as macOS renders it in the light
// appearance: from its Icon Composer icon, with the tile, the glass and the
// shadows the system adds. docs/icon/AppIcon.png comes from it, for the social
// preview and anywhere else the icon is needed as an image.
//
//   FOR_RELEASE=1 Scripts/package_app.sh release   (or any bundle with the icon)
//   swift Scripts/render_icon.swift build/DevSweep.app docs/icon/AppIcon.png 1024

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: swift Scripts/render_icon.swift <app> <png> [side]\n".utf8))
    exit(2)
}
let side = arguments.count > 3 ? Int(arguments[3]) ?? 1024 : 1024
// Absolute: given a relative path, NSWorkspace answers with a generic document icon.
let app = URL(fileURLWithPath: arguments[1]).standardizedFileURL.path
guard FileManager.default.fileExists(atPath: "\(app)/Contents/Info.plist") else {
    FileHandle.standardError.write(Data("render_icon.swift: \(app) is not an app bundle\n".utf8))
    exit(1)
}
let icon = NSWorkspace.shared.icon(forFile: app)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
    icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
}
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: arguments[2]))
