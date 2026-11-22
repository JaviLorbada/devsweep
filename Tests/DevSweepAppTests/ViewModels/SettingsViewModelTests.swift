import Foundation
import Testing
@testable import DevSweepApp

@MainActor
@Suite("Settings")
struct SettingsViewModelTests {
    @Test
    func `Open at login is off until macOS says the app is registered`() {
        let loginItem = FakeLoginItem()
        let settings = SettingsViewModel(loginItem: loginItem)
        settings.refresh()
        #expect(!settings.opensAtLogin, "never registered, macOS says not found")

        loginItem.status = .enabled
        settings.refresh()
        #expect(settings.opensAtLogin)
        #expect(!settings.needsApproval)
    }

    @Test
    func `turning Open at login on registers the app, and off unregisters it`() {
        let loginItem = FakeLoginItem()
        let settings = SettingsViewModel(loginItem: loginItem)
        settings.refresh()
        settings.setOpensAtLogin(true)
        #expect(loginItem.asked == [true])
        #expect(settings.opensAtLogin)

        settings.setOpensAtLogin(false)
        #expect(loginItem.asked == [true, false])
        #expect(!settings.opensAtLogin)
        #expect(settings.loginItemError == nil)
    }

    @Test
    func `a login item waiting on approval shows on, says so, and opens Login Items`() {
        let loginItem = FakeLoginItem()
        loginItem.registeredStatus = .requiresApproval
        let settings = SettingsViewModel(loginItem: loginItem)
        settings.setOpensAtLogin(true)
        #expect(settings.opensAtLogin)
        #expect(settings.needsApproval)

        settings.openLoginItems()
        #expect(loginItem.openedLoginItems == 1)
    }

    @Test
    func `a login item removed in System Settings shows off once Settings reads it again`() {
        let loginItem = FakeLoginItem()
        loginItem.status = .enabled
        let settings = SettingsViewModel(loginItem: loginItem)
        settings.refresh()
        #expect(settings.opensAtLogin)

        loginItem.status = .notRegistered
        settings.refresh()
        #expect(!settings.opensAtLogin)
        #expect(!settings.needsApproval)
    }

    @Test
    func `macOS refusing the change says why until the next one, and leaves Open at login as it was`() {
        let loginItem = FakeLoginItem()
        loginItem.refusal = NSError(
            domain: "SMAppServiceErrorDomain",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
        let settings = SettingsViewModel(loginItem: loginItem)
        settings.setOpensAtLogin(true)
        #expect(loginItem.asked == [true])
        #expect(!settings.opensAtLogin)
        #expect(settings.loginItemError == "Open at login didn't change: Operation not permitted")

        loginItem.refusal = nil
        settings.setOpensAtLogin(true)
        #expect(settings.opensAtLogin)
        #expect(settings.loginItemError == nil)
    }
}
