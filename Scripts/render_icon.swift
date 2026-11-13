// Draws an Icon Composer icon into a PNG as macOS shows it in Finder: the
// tile on the icon grid, 824 of 1024 points with 100-point margins, over a
// soft shadow. Icon Composer's own renderer draws the tile, in the light or
// the dark appearance, straight from the .icon file; no app needs building.
// docs/icon/AppIcon.png, for the social preview, and the README's icons come
// from it.
//
//   swift Scripts/render_icon.swift docs/icon/AppIcon.icon docs/icon/AppIcon.png 1024
//   swift Scripts/render_icon.swift docs/icon/AppIcon.icon docs/icon/readme-light.png 256
//   swift Scripts/render_icon.swift docs/icon/AppIcon.icon docs/icon/readme-dark.png 256 dark

import AppKit

func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("render_icon.swift: \(message)\n".utf8))
    exit(status)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fail("usage: swift Scripts/render_icon.swift <icon> <png> [side] [light|dark]", status: 2)
}
let icon = URL(fileURLWithPath: arguments[1]).standardizedFileURL.path
let output = arguments[2]
let side = arguments.count > 3 ? Int(arguments[3]) ?? 1024 : 1024
let appearance = arguments.count > 4 ? arguments[4] : "light"
guard ["light", "dark"].contains(appearance) else { fail("the appearance is light or dark, not \(appearance)") }
guard FileManager.default.fileExists(atPath: "\(icon)/icon.json") else { fail("\(icon) is not an Icon Composer icon") }

/// Runs a tool and returns what it printed, or stops with what it said.
func run(_ tool: String, _ toolArguments: [String]) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = toolArguments
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { fail("couldn't run \(tool): \(error.localizedDescription)") }
    let printed = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fail("\(tool) failed:\n\(printed)") }
    return printed
}

// Icon Composer's renderer ships inside Icon Composer, next to Xcode's developer folder.
let developer = run("/usr/bin/xcode-select", ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
let ictool = URL(fileURLWithPath: developer)
    .deletingLastPathComponent()
    .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool").path
guard FileManager.default.isExecutableFile(atPath: ictool) else { fail("no Icon Composer renderer at \(ictool)") }

// The tile, as Icon Composer draws it.
let scale = CGFloat(side) / 1024
let tileSide = Int((824 * scale).rounded())
let work = FileManager.default.temporaryDirectory.appendingPathComponent("render_icon-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }
let tilePNG = work.appendingPathComponent("tile.png").path
_ = run(ictool, [icon, "--export-image", "--output-file", tilePNG, "--platform", "macOS",
                 "--rendition", appearance == "dark" ? "Dark" : "Default",
                 "--width", "\(tileSide)", "--height", "\(tileSide)", "--scale", "1"])
guard let tile = NSImage(contentsOfFile: tilePNG) else { fail("Icon Composer's renderer drew nothing") }

// The tile on the icon grid, over the shadow macOS draws under icons.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.25)
shadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
shadow.shadowBlurRadius = 32 * scale
shadow.set()
let margin = (CGFloat(side) - CGFloat(tileSide)) / 2
tile.draw(in: NSRect(x: margin, y: margin, width: CGFloat(tileSide), height: CGFloat(tileSide)))
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: output))
