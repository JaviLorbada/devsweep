import Observation
import ServiceManagement

/// Settings' own state and actions, beside the preferences it binds: Open
/// at login. macOS keeps the login item, and the person can remove it in
/// System Settings as well, so Settings reads its status again whenever it
/// shows, and the preferences keep no copy.
@MainActor
@Observable
final class SettingsViewModel {
    /// The login item as macOS last reported it.
    private(set) var loginItemStatus = SMAppService.Status.notRegistered
    /// Why macOS refused the last change to Open at login, until the next
    /// one.
    private(set) var loginItemError: String?
    @ObservationIgnored private let loginItem: any LoginItemRegistering

    init(loginItem: any LoginItemRegistering) {
        self.loginItem = loginItem
    }

    /// On once registered, approved or still waiting on approval.
    var opensAtLogin: Bool {
        self.loginItemStatus == .enabled || self.loginItemStatus == .requiresApproval
    }

    /// Registered, but macOS opens the app at login only once the person
    /// allows it in Login Items.
    var needsApproval: Bool {
        self.loginItemStatus == .requiresApproval
    }

    /// Reads the status again, as Settings shows or comes back to the front.
    func refresh() {
        self.loginItemStatus = self.loginItem.status
    }

    /// Registers the app as a login item, or unregisters it, and reads what
    /// macOS made of it: registering may leave it waiting on approval.
    func setOpensAtLogin(_ opens: Bool) {
        self.loginItemError = nil
        do {
            if opens {
                try self.loginItem.register()
            } else {
                try self.loginItem.unregister()
            }
        } catch {
            self.loginItemError = "Open at login didn't change: \(error.localizedDescription)"
        }
        self.refresh()
    }

    func openLoginItems() {
        self.loginItem.openLoginItems()
    }
}
