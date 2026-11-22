import AppKit

/// The app's activation policy: a regular app, with a Dock icon and menus,
/// or an accessory, with neither, whose menu bar item stays.
@MainActor
struct ActivationPolicyDockIcon: DockIconShowing {
    func setShown(_ shown: Bool) {
        NSApplication.shared.setActivationPolicy(shown ? .regular : .accessory)
    }
}
