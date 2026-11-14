import DevSweepKit
import SwiftUI

/// The menu bar's commands: About, Scan Again in the File menu, the chart
/// and the inspector in the View menu; `HelpCommands` has the Help menu.
/// Template items that would do nothing, such as New Window, are replaced;
/// the Edit menu stays for text fields.
struct AppCommands: Commands {
    let scan: ScanModel
    let window: WindowViewModel
    @Environment(\.openWindow) private var openWindow

    /// What choosing the inspector's item does, as a menu item whose title
    /// changes says it, rather than "Toggle Inspector".
    static func inspectorTitle(shown: Bool) -> String {
        shown ? "Hide Inspector" : "Show Inspector"
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(BuildIdentity.current.appName)") { self.openWindow(id: "about") }
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
                    set: { if $0 { self.window.showChart(style) } }))
                    .keyboardShortcut(style == .ring ? "1" : "2")
            }
            Divider()
            Button(Self.inspectorTitle(shown: self.window.inspectorShown)) { self.window.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
