import AppKit
import DevSweepKit

/// Quits Xcode and Simulator before a clean that needs them closed. Live, it
/// asks them as choosing Quit would; tests say what quitting does.
protocol AppQuitting: Sendable {
    /// Asks `apps` to quit and waits for them, up to a limit. Whether they all did.
    func quit(_ apps: [DeveloperApp]) async -> Bool
}

/// Asks the apps to quit, as choosing Quit would, and waits up to 15 seconds.
struct WorkspaceAppQuitter: AppQuitting {
    @MainActor
    func quit(_ apps: [DeveloperApp]) async -> Bool {
        let running = apps
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier) }
        running.forEach { $0.terminate() }
        for _ in 0..<60 {
            if running.allSatisfy(\.isTerminated) { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return running.allSatisfy(\.isTerminated)
    }
}

/// Xcode and Simulator, asked of `NSRunningApplication`, with a callback when
/// either launches or quits.
final class WorkspaceRunningApps: RunningAppsChecking, @unchecked Sendable {
    @MainActor var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    @MainActor
    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier,
                      DeveloperApp.allCases.contains(where: { $0.bundleIdentifier == id }) else { return }
                MainActor.assumeIsolated { self?.onChange?() }
            })
        }
    }

    func isRunning(_ app: DeveloperApp) async -> Bool {
        await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
                .contains { !$0.isTerminated }
        }
    }
}
