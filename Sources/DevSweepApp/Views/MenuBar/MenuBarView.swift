import AppKit
import DevSweepKit
import SwiftUI

/// The menu bar item: the icon's ring as a glyph, then the boot volume's
/// free space.
struct MenuBarLabel: View {
    @Environment(ScanModel.self) private var scan
    @Environment(MenuBarViewModel.self) private var menuBar

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarGlyph(showsUpdateDot: self.menuBar.showsUpdateDot).image)
            if let space = scan.diskSpace {
                Text(Self.title(space))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.scan.diskSpace
            .map { "\(SizeText.of(kilobytes: $0.freeKilobytes)) free" } ?? "\(ProductInfo.name)")
    }

    /// The text beside the glyph, such as "48.2 GB". A plain string with
    /// nothing interpolated into it: an Image interpolated into a String
    /// becomes its type's description, and that was what the menu bar showed.
    static func title(_ space: DiskSpace) -> String {
        SizeText.of(kilobytes: space.freeKilobytes)
    }
}

/// The menu bar item's glyph: the icon's ring in one color, and an orange
/// dot in its middle while an update waits. At this size the icon's gaps
/// would be half a point, so they are wider here.
@MainActor
struct MenuBarGlyph {
    static let side: CGFloat = 16
    static let lineWidth: CGFloat = 2
    /// The ring's radius to the middle of its stroke, a point in from the edge.
    static let radius = side / 2 - 1 - lineWidth / 2
    /// The gap between two segments, as a share of the ring.
    static let gap = 0.045
    /// The update dot's diameter: inside the ring, two points clear of it.
    static let dotDiameter: CGFloat = 6

    let showsUpdateDot: Bool

    /// Without the dot, a template image, so the menu bar draws it in its own
    /// text color, light or dark. With it, not a template, or the menu bar
    /// would draw the dot in its text color too: the ring takes that color
    /// itself. VoiceOver reads the item by the image's description.
    var image: NSImage {
        let image = NSImage(size: NSSize(width: Self.side, height: Self.side), flipped: false) { rect in
            self.draw(in: rect)
            return true
        }
        image.isTemplate = !self.showsUpdateDot
        image.accessibilityDescription = self.showsUpdateDot
            ? "\(ProductInfo.name), update available"
            : ProductInfo.name
        return image
    }

    private func draw(in rect: NSRect) {
        (self.showsUpdateDot ? Palette.menuBarTextColor : .black).setStroke()
        self.drawRing(in: rect)
        if self.showsUpdateDot {
            self.drawDot(in: rect)
        }
    }

    /// The ring's segments, clockwise from the top as the icon draws them,
    /// in the stroke color set.
    private func drawRing(in rect: NSRect) {
        for segment in IconRing.segments(gap: Self.gap) {
            let path = NSBezierPath()
            path.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY),
                radius: Self.radius,
                startAngle: 90 - segment.from * 360,
                endAngle: 90 - segment.to * 360,
                clockwise: true)
            path.lineWidth = Self.lineWidth
            path.lineCapStyle = .butt
            path.stroke()
        }
    }

    private func drawDot(in rect: NSRect) {
        let dot = NSRect(
            x: rect.midX - Self.dotDiameter / 2,
            y: rect.midY - Self.dotDiameter / 2,
            width: Self.dotDiameter,
            height: Self.dotDiameter)
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }
}

/// What the menu bar item opens: what the last scan found per family, when
/// that was, the two things to do from here, and, listed as menu items in
/// groups, what the app menu has: About and Check for Updates…, then
/// Settings…, then Quit, which with Show in Dock off and the window closed
/// are otherwise out of reach. While an update waits, its row heads the
/// list, in a group of its own: Update Available…, or Install Update and
/// Relaunch once it is downloaded.
/// Its buttons go through `MenuBarViewModel`, except for opening the
/// window, Settings and About, which only a view can do.
/// It sits on a material, where
/// the hierarchical styles turn vibrant, and in the light appearance vibrancy
/// drew `.secondary` darker than `.primary`: the volume name gray, its free
/// space black. So the text is in plain colors, the label color's values over
/// the window's muted color, which keep that order in both appearances.
struct MenuBarPanel: View {
    @Environment(ScanModel.self) private var scan
    @Environment(MenuBarViewModel.self) private var menuBar
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// The menu bar's text color, plain. The material makes
    /// `Color(nsColor: .labelColor)` vibrant, as it does `.primary`.
    private static let textColor = Color(nsColor: Palette.menuBarTextColor)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                // A long volume name gives way before the free space does.
                Text(self.scan.volumeName).font(.headline).lineLimit(1)
                Spacer()
                if let space = scan.diskSpace {
                    Text(space.freeOfTotal)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.muted)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .foregroundStyle(Self.textColor)
            VStack(spacing: 6) {
                ForEach(Family.allCases) { family in
                    HStack(spacing: 8) {
                        Dot(color: Palette.color(family))
                        Text(family.name)
                        Spacer()
                        Text(self.scan.tally.measuredKilobytes(of: family).map { SizeText.of(kilobytes: $0) } ?? "–")
                            .monospacedDigit()
                            .foregroundStyle(.muted)
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                }
                Divider()
                HStack {
                    Text("Reclaimable").fontWeight(.semibold)
                    Spacer()
                    Text(SizeText.of(kilobytes: self.scan.tally.reclaimableKilobytes)).fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
            }
            .foregroundStyle(Self.textColor)
            Text(StatusText.menuBar(self.scan.statusFacts))
                .font(.caption)
                .foregroundStyle(.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(self.menuBar.scanTitle) { self.menuBar.scanNow() }
                    .disabled(!self.menuBar.canScanNow)
                Spacer()
                Button("Open \(ProductInfo.name)") {
                    self.openWindow(id: "main")
                    self.menuBar.bringToFront()
                }
                .buttonStyle(.prominentAction)
            }
            .controlSize(.large)
            Divider()
            VStack(spacing: 0) {
                if let update = self.menuBar.waitingUpdate {
                    Button {
                        self.menuBar.chooseWaitingUpdate()
                    } label: {
                        self.menuItem(update.title)
                    }
                    PanelMenuSeparator()
                }
                Button {
                    self.openWindow(id: "about")
                    self.menuBar.bringToFront()
                } label: {
                    self.menuItem("About \(BuildIdentity.current.appName)")
                }
                if self.menuBar.showsCheckForUpdates {
                    Button {
                        self.menuBar.checkForUpdates()
                    } label: {
                        self.menuItem(AppCommands.checkForUpdatesTitle)
                    }
                    .disabled(!self.menuBar.canCheckForUpdates)
                }
                PanelMenuSeparator()
                Button {
                    self.openSettings()
                    self.menuBar.bringToFront()
                } label: {
                    self.menuItem("Settings…", shortcut: "⌘,")
                }
                .keyboardShortcut(",")
                PanelMenuSeparator()
                Button {
                    self.menuBar.quit()
                } label: {
                    self.menuItem("Quit \(BuildIdentity.current.appName)", shortcut: "⌘Q")
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(PanelMenuItemStyle())
            .foregroundStyle(Self.textColor)
            // The highlights reach past the panel's padding, as a menu's do,
            // and the titles and separators line up with the text above.
            .padding(.horizontal, -PanelMenuItemStyle.inset)
        }
        .padding(16)
        .frame(width: 280)
    }

    /// A menu item's title, and its shortcut to the right, as a menu shows it.
    private func menuItem(_ title: String, shortcut: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .foregroundStyle(.muted)
                    .accessibilityHidden(true)
            }
        }
    }
}
