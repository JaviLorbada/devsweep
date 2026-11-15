import DevSweepKit
import SwiftUI

/// The menu bar's commands: About and Check for Updates…, Scan Again in the
/// File menu, the chart and the inspector in the View menu; `HelpCommands`
/// has the Help menu.
/// Template items that would do nothing, such as New Window, are replaced;
/// the Edit menu stays for text fields.
struct AppCommands: Commands {
    let scan: ScanModel
    let window: WindowViewModel
    let updates: UpdatesModel
    @Environment(\.openWindow) private var openWindow

    /// What choosing the inspector's item does, as a menu item whose title
    /// changes says it, rather than "Toggle Inspector".
    static func inspectorTitle(shown: Bool) -> String {
        shown ? "Hide Inspector" : "Show Inspector"
    }

    /// With an ellipsis: it opens a window, Sparkle's, to say what it found.
    static let checkForUpdatesTitle = "Check for Updates…"

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(BuildIdentity.current.appName)") { self.openWindow(id: "about") }
            if self.updates.isAvailable {
                Button(Self.checkForUpdatesTitle) {
                    self.updates.checkForUpdates()
                }
                .disabled(!self.updates.canCheck)
            }
        }
        CommandGroup(replacing: .newItem) {
            Button(self.scan.isScanning ? "Stop Scan" : "Scan Again") {
                self.scan.isScanning ? self.scan.stopScan() : self.scan.scan()
            }
            .keyboardShortcut("r")
            .disabled(!self.scan.canScanOrStop)
        }
        CommandGroup(before: .toolbar) {
            ForEach(WindowViewModel.ChartStyle.allCases) { style in
                Toggle(style.rawValue, isOn: Binding(
                    get: { self.window.screen == .overview && self.window.chartStyle == style },
                    set: {
                        if $0 {
                            self.window.showChart(style)
                        }
                    }))
                    .keyboardShortcut(style == .ring ? "1" : "2")
            }
            Divider()
            Button(Self.inspectorTitle(shown: self.window.inspectorShown)) { self.window.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
