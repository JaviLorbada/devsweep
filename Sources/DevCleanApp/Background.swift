import DevCleanKit
import Foundation
import UserNotifications

/// When the app scans on its own while it runs: a day after the last scan.
enum ScanSchedule {
    static let interval: TimeInterval = 24 * 60 * 60

    static func isDue(lastScan: Date?, now: Date) -> Bool {
        guard let lastScan else { return false }
        return now.timeIntervalSince(lastScan) >= self.interval
    }
}

/// Whether DerivedData grew enough since the last scan to say so.
enum GrowthCheck {
    struct Alert: Equatable {
        let title: String
        let body: String
    }

    /// An alert when DerivedData grew by more than `thresholdGigabytes`
    /// since the previous scan; nil on a first scan or below the threshold.
    static func derivedData(previousKilobytes: Int64?, currentKilobytes: Int64?, thresholdGigabytes: Int) -> Alert? {
        guard let previous = previousKilobytes, let current = currentKilobytes else { return nil }
        let growth = current - previous
        guard growth > Int64(thresholdGigabytes) * 1024 * 1024 else { return nil }
        return Alert(
            title: "DerivedData grew by \(SizeText.of(kilobytes: growth))",
            body: "It holds \(SizeText.of(kilobytes: current)) now, up from \(SizeText.of(kilobytes: previous)) at "
                + "the last scan. "
                + "Open \(ProductInfo.name) to clean it.")
    }
}

/// Posts the app's notifications. Tests use one that records them.
protocol NotificationPoster: Sendable {
    func post(title: String, body: String) async
}

/// Notification Center. Asks for permission the first time it has something
/// to say, not at launch. Without a bundle, as `swift run` starts the app,
/// there is no Notification Center to post to, so it stays quiet.
struct UserNotificationPoster: NotificationPoster {
    func post(title: String, body: String) async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        guard await (try? center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

/// Posts nothing; what tests and unattended runs use.
struct SilentNotificationPoster: NotificationPoster {
    func post(title: String, body: String) async {}
}
