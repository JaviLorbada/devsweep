import DevSweepKit
import SwiftUI

/// Settings > General's updates section: whether the app looks for updates
/// on its own, and installs them. Sparkle asks the same on the second
/// launch; either answer shows here.
struct UpdateSettings: View {
    let updates: UpdatesModel

    var body: some View {
        let updates = self.updates
        Section {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updates.checksAutomatically },
                set: { checks in
                    updates.setChecksAutomatically(checks)
                }))
            Toggle("Download and install updates automatically", isOn: Binding(
                get: { updates.downloadsAutomatically },
                set: { downloads in
                    updates.setDownloadsAutomatically(downloads)
                }))
                .disabled(!updates.checksAutomatically)
        } footer: {
            Text(
                "With automatic checks, once a day \(ProductInfo.name) asks GitHub for its latest release, sending "
                    + "only its own version: the one connection it makes. Check for Updates… in the "
                    + "\(ProductInfo.name) menu asks now.")
                .settingsFooter()
        }
    }
}
