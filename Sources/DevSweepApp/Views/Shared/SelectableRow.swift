import SwiftUI

/// A row of a listing screen: selected by a click, by Space or by
/// VoiceOver's Select, and drawn selected as a table row is.
struct SelectableRow: ViewModifier {
    let isSelected: Bool
    /// What VoiceOver reads for the row.
    let label: String
    let select: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(height: 40)
            .tableRowSelection(self.isSelected)
            .contentShape(Rectangle())
            .onTapGesture { self.select() }
            .focusable()
            .onKeyPress(.space) { self.select(); return .handled }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(self.label)
            .accessibilityAddTraits(self.isSelected ? .isSelected : [])
            .accessibilityAction(named: "Select") { self.select() }
    }
}

extension View {
    func selectableRow(selected: Bool, label: String, select: @escaping @MainActor () -> Void) -> some View {
        modifier(SelectableRow(isSelected: selected, label: label, select: select))
    }
}
