import AppKit
import SwiftUI

@main
struct DevCleanApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    init() {
        // A one-window utility has no session worth restoring, and restored
        // state can say the window was closed, after which the app launched
        // with no window at all. Registered before AppKit reads it.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    var body: some Scene {
        Window("DevClean", id: "main") {
            ContentView()
                .environment(model)
                .containerBackground(Palette.backdrop, for: .window)
                // A fixed ideal size: SwiftUI animates the window to the
                // content's ideal size whenever an animated change alters it,
                // and with flexible content that size followed every scan event.
                .frame(
                    minWidth: WindowLayout.minimumWidth, idealWidth: 1280, maxWidth: .infinity,
                    minHeight: WindowLayout.minimumHeight, idealHeight: 860, maxHeight: .infinity
                )
        }
        .defaultSize(width: 1280, height: 860)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
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

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugLaunch.isRequested {
            let state = "hidden \(NSApplication.shared.isHidden), windows \(NSApplication.shared.windows.map { "\($0.isVisible)/\($0.isMiniaturized)" })"
            FileHandle.standardError.write(Data("debug launch: launched, \(state)\n".utf8))
        }
        #endif
        // Run from a plain executable, the app has no bundle telling macOS it
        // is a regular app with a Dock icon and a menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

}
