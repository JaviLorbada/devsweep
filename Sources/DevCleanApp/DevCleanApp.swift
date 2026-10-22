import AppKit
import DevCleanKit
import SwiftUI

@main
struct DevCleanApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel(notifier: Self.notifier)

    /// Development runs, with or without a fake home, never ask to notify.
    private static var notifier: NotificationPoster {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if DebugLaunch.isRequested || environment["DEVCLEAN_SNAPSHOT"] != nil || environment["DEVCLEAN_SKIP"] != nil {
            return SilentNotificationPoster()
        }
        #endif
        return UserNotificationPoster()
    }

    init() {
        // A one-window utility has no session worth restoring, and restored
        // state can say the window was closed, after which the app launched
        // with no window at all. Registered before AppKit reads it.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    var body: some Scene {
        Window(ProductInfo.name, id: "main") {
            ContentView()
                .environment(self.model)
                .containerBackground(Palette.backdrop, for: .window)
                // A fixed ideal size: SwiftUI animates the window to the
                // content's ideal size whenever an animated change alters it,
                // and with flexible content that size followed every scan event.
                .frame(
                    minWidth: WindowLayout.minimumWidth, idealWidth: 1280, maxWidth: .infinity,
                    minHeight: WindowLayout.minimumHeight, idealHeight: 860, maxHeight: .infinity)
        }
        .defaultSize(width: 1280, height: 860)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button(self.model.isScanning ? "Stop Scan" : "Scan Again") {
                    self.model.isScanning ? self.model.stopScan() : self.model.scan()
                }
                .keyboardShortcut("r")
                .disabled(self.model.engine == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(self.model)
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(self.model)
        } label: {
            MenuBarLabel()
                .environment(self.model)
        }
        .menuBarExtraStyle(.window)
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

    /// The menu bar item keeps the app, and its daily scan, running when the
    /// window closes; the item's Open DevClean brings the window back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
