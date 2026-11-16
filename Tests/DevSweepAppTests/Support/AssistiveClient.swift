import AppKit

/// SwiftUI builds a window's accessibility tree only for an assistive app,
/// such as VoiceOver, which says it is listening by setting the
/// application's `AXEnhancedUserInterface`. The tests that read the tree
/// need it, and nothing in a test process clears it again; set by the first
/// of those tests, it would leave the others' views drawn with the tree or
/// without it, by the order they ran in. So it is set once, the first time
/// any test builds the app, and every test that draws the app's views runs
/// with the tree, whichever runs first.
@MainActor
enum AssistiveClient {
    /// Whether the application was told an assistive app is listening; set
    /// on first use.
    static let isListening: Bool = {
        let application = NSApplication.shared
        let setValue = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        guard application.responds(to: setValue) else {
            return false
        }
        _ = application.perform(setValue, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        return true
    }()
}
