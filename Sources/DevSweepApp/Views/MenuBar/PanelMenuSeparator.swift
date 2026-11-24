import SwiftUI

/// A line between two groups of the menu bar panel's menu items, as a menu
/// draws one: as wide as the items' titles, inside their highlights, with
/// half a row of room above and below.
struct PanelMenuSeparator: View {
    var body: some View {
        Divider()
            .padding(.horizontal, PanelMenuItemStyle.inset)
            .padding(.vertical, 5)
    }
}
