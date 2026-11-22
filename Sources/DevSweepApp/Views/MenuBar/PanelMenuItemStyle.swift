import SwiftUI

/// A button in the menu bar panel's list of actions, drawn as a menu item:
/// a row as wide as the list, highlighted under the pointer and while
/// pressed, and dimmed while it can't be used.
struct PanelMenuItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let highlighted = self.isEnabled && (self.isHovered || self.configuration.isPressed)
            self.configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.fill.tertiary.opacity(highlighted ? 1 : 0), in: RoundedRectangle(cornerRadius: 6))
                .opacity(self.isEnabled ? 1 : 0.5)
                .contentShape(Rectangle())
                .onHover { self.isHovered = $0 }
        }
    }
}
