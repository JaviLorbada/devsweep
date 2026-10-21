import AppKit
import SwiftUI

@main
struct DevCleanApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("DevClean", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button(model.isScanning ? "Stop Scan" : "Scan Again") {
                    model.isScanning ? model.stopScan() : model.scan()
                }
                .keyboardShortcut("r")
                .disabled(model.engine == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run from a plain executable, the app has no bundle telling macOS it
        // is a regular app with a Dock icon and a menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
