import Foundation
import Testing
@testable import DevSweepApp

@Suite("Launch event")
struct LaunchEventTests {
    /// The event macOS sends as it launches the app, marked as it marks one
    /// for a login item when asked.
    private func event(_ id: AEEventID, mark: AEKeyword? = nil) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: id,
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        if let mark {
            event.setParam(NSAppleEventDescriptor(enumCode: mark), forKeyword: keyAEPropData)
        }
        return event
    }

    @Test
    func `macOS opening the app as a login item marks a launch at login`() {
        #expect(LaunchEvent.isAtLogin(self.event(kAEOpenApplication, mark: keyAELaunchedAsLogInItem)))
    }

    @Test
    func `the person opening the app is no launch at login`() {
        #expect(!LaunchEvent.isAtLogin(self.event(kAEOpenApplication)))
        #expect(!LaunchEvent.isAtLogin(self.event(kAEOpenApplication, mark: keyAELaunchedAsServiceItem)))
        #expect(!LaunchEvent.isAtLogin(nil))
    }

    @Test
    func `only an open-application event says it`() {
        #expect(!LaunchEvent.isAtLogin(self.event(kAEOpenDocuments, mark: keyAELaunchedAsLogInItem)))
    }
}
