import Foundation

/// The open-application event that comes with a launch. macOS marks it when
/// it opens the app as a login item, and SwiftUI then opens no window: a
/// launch at login should only do what suits it, Apple's documentation
/// says, such as not opening a new document.
enum LaunchEvent {
    /// Whether macOS opened the app at login, rather than the person.
    static func isAtLogin(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventClass == kCoreEventClass, event.eventID == kAEOpenApplication else {
            return false
        }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
