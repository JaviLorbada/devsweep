import SwiftUI

extension Text {
    /// A Settings section's footer: smaller, muted, and wrapped to the
    /// window's width.
    func settingsFooter() -> some View {
        font(.callout).foregroundStyle(.muted).fixedSize(horizontal: false, vertical: true)
    }
}
