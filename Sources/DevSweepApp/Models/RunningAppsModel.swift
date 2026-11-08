import DevSweepKit
import Observation

/// Whether Xcode and Simulator are open, and quitting them before a clean
/// that needs them closed.
@MainActor
@Observable
final class RunningAppsModel: RunningApps {
    private(set) var running: Set<DeveloperApp> = []
    private let checker: any RunningAppsChecking
    private let quitter: any AppQuitting

    /// - Parameters:
    ///   - checker: says what runs: the workspace, live; a test's set otherwise.
    ///   - quitter: quits them: as choosing Quit would, live.
    init(checker: any RunningAppsChecking, quitter: any AppQuitting) {
        self.checker = checker
        self.quitter = quitter
    }

    func refresh() async {
        var running = Set<DeveloperApp>()
        for app in DeveloperApp.allCases where await self.checker.isRunning(app) {
            running.insert(app)
        }
        self.running = running
    }

    /// Asks `apps` to quit and waits for them. Whether they all did.
    func quit(_ apps: [DeveloperApp]) async -> Bool {
        let quit = await self.quitter.quit(apps)
        await self.refresh()
        return quit
    }
}
