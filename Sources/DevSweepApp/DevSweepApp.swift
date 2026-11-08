import AppKit
import DevSweepKit
import SwiftUI

@main
struct DevSweepApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel(notifier: Self.notifier)

    /// Development runs, with or without a fake home, never ask to notify.
    private static var notifier: NotificationPoster {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if DebugLaunch.isRequested || environment["DEVSWEEP_SNAPSHOT"] != nil || environment["DEVSWEEP_SKIP"] != nil {
            return SilentNotificationPoster()
        }
        #endif
        return UserNotificationPoster()
    }

    init() {
        #if DEBUG
        AppIconRenderer.runIfAsked()
        #endif
        // A one-window utility has no session worth restoring, and restored
        // state can say the window was closed, after which the app launched
        // with no window at all. Registered before AppKit reads it.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    var body: some Scene {
        Window(ProductInfo.name, id: "main") {
            ContentView()
                .environment(models: self.model)
                .task { await self.model.windowAppeared() }
                .containerBackground(Palette.backdrop, for: .window)
                // A fixed ideal size: SwiftUI animates the window to the
                // content's ideal size whenever an animated change alters it,
                // and with flexible content that size followed every scan event.
                .frame(
                    minWidth: WindowLayout.minimumWidth,
                    idealWidth: 1280,
                    maxWidth: .infinity,
                    minHeight: WindowLayout.minimumHeight,
                    idealHeight: 860,
                    maxHeight: .infinity)
        }
        .defaultSize(width: 1280, height: 860)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
        .commands { AppCommands(model: self.model) }

        Window("About \(ProductInfo.name)", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        // The app menu opens it; it needs no item in the Window menu.
        .commandsRemoved()

        Settings {
            SettingsView()
                .environment(models: self.model)
        }

        MenuBarExtra(isInserted: Binding(
            get: { self.model.preferences.showInMenuBar },
            set: { self.model.preferences.showInMenuBar = $0 }))
        {
            MenuBarPanel()
                .environment(models: self.model)
        } label: {
            MenuBarLabel()
                .environment(models: self.model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugLaunch.isRequested {
            let state = "hidden \(NSApplication.shared.isHidden), windows "
                + "\(NSApplication.shared.windows.map { "\($0.isVisible)/\($0.isMiniaturized)" })"
            FileHandle.standardError.write(Data("debug launch: launched, \(state)\n".utf8))
        }
        #endif
        // Run from a plain executable, the app has no bundle telling macOS it
        // is a regular app with a Dock icon and a menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    /// The menu bar item keeps the app, and its daily scan, running when the
    /// window closes; the item's Open DevSweep brings the window back.
    /// Without the item, closing the window quits, as a utility does.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(UserDefaults.standard.object(forKey: Preferences.Key.showInMenuBar) as? Bool ?? true)
    }
}

/// The menu bar's commands: About, Scan Again in the File menu, the chart
/// and the inspector in the View menu, and the project's pages and its tip
/// jar under Help.
/// Template items that would do nothing, such as New Window and a Help book
/// there is none of, are replaced; the Edit menu stays for text fields.
struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    /// What choosing the inspector's item does, as a menu item whose title
    /// changes says it, rather than "Toggle Inspector".
    static func inspectorTitle(shown: Bool) -> String {
        shown ? "Hide Inspector" : "Show Inspector"
    }

    /// In title case, as menu items are written.
    static let reportProblemTitle = "Report a Problem"
    /// Opens the tip jar.
    static let supportTitle = "Support \(ProductInfo.name)"

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(ProductInfo.name)") { self.openWindow(id: "about") }
        }
        CommandGroup(replacing: .newItem) {
            Button(self.model.scan.isScanning ? "Stop Scan" : "Scan Again") {
                self.model.scan.isScanning ? self.model.scan.stopScan() : self.model.scan.scan()
            }
            .keyboardShortcut("r")
            .disabled(!self.model.scan.canScanOrStop)
        }
        CommandGroup(before: .toolbar) {
            ForEach(WindowViewModel.ChartStyle.allCases) { style in
                Toggle(style.rawValue, isOn: Binding(
                    get: { self.model.window.screen == .overview && self.model.window.chartStyle == style },
                    set: { if $0 { self.model.window.showChart(style) } }))
                    .keyboardShortcut(style == .ring ? "1" : "2")
            }
            Divider()
            Button(Self.inspectorTitle(shown: self.model.window.inspectorShown)) { self.model.window.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .help) {
            Button("\(ProductInfo.name) on GitHub") { self.openURL(ProductInfo.repository) }
            Button(Self.reportProblemTitle) { self.openURL(ProductInfo.issues) }
            Divider()
            Button(Self.supportTitle) { self.openURL(ProductInfo.tipJar) }
        }
    }
}
