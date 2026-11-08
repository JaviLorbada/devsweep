import DevSweepKit
import Observation

/// The three Android screens' own state: Android Studio, the SDK and its
/// emulators, and Gradle's caches. Each keeps its own selection.
@MainActor
@Observable
final class AndroidViewModel {
    /// The entry selected on each screen, by path.
    private(set) var selectedPaths: [WindowViewModel.Screen: String] = [:]
    private let window: WindowViewModel
    private let scan: ScanModel
    private let preferences: Preferences

    init(window: WindowViewModel, scan: ScanModel, preferences: Preferences) {
        self.window = window
        self.scan = scan
        self.preferences = preferences
    }

    /// Days unused before an emulator or system image is flagged.
    var staleDays: Int {
        self.preferences.staleDays
    }

    /// What the Android screen showing lists, in the order it shows them.
    var entries: [AndroidEntry] {
        guard let android = self.scan.android else { return [] }
        switch self.window.screen {
        case .androidStudios: return android.studios
        case .androidSDK:
            return android.emulators + android.systemImages + android.platforms + android.buildTools
                + android.otherSDKParts
        case .gradleCaches: return android.gradleCaches
        default: return []
        }
    }

    /// The entry selected on this screen, or the first flagged one, or the first.
    var current: AndroidEntry? {
        let entries = self.entries
        return entries.first { $0.path == self.selectedPaths[self.window.screen] }
            ?? entries.first { $0.flagReason(staleDays: self.staleDays) != nil }
            ?? entries.first
    }

    /// Selects `entry` on the screen showing.
    func select(_ entry: AndroidEntry) {
        self.selectedPaths[self.window.screen] = entry.path
    }

    /// What the screen showing says under its title.
    var subtitle: String {
        let (android, isLoading) = (self.scan.android, self.scan.isLoadingAndroid)
        return switch self.window.screen {
        case .androidStudios: StatusText.androidStudios(android, isLoading: isLoading)
        case .androidSDK: StatusText.androidSDK(android, isLoading: isLoading)
        case .gradleCaches: StatusText.gradleCaches(android, isLoading: isLoading)
        default: ""
        }
    }
}
